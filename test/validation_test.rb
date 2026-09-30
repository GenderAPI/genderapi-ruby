# frozen_string_literal: true

require_relative "test_helper"

# Invalid input must raise before any network request.
class ValidationTest < StubTest
  def assert_invalid(field = nil, &block)
    error = assert_raises(GenderAPI::ValidationError, &block)
    assert_equal field, error.field if field
    assert_equal 0, @stub.connections
    error
  end

  def test_type
    assert_invalid("type") { client.gender("phone", "Onur") }
    assert_invalid("type") { client.gender(nil, "Onur") }
  end

  def test_value
    assert_invalid("value") { client.name("") }
    assert_invalid("value") { client.name("   ") }
    assert_invalid("value") { client.name(" 　") }
    assert_invalid("value") { client.name(nil) }
    assert_invalid("value") { client.name(42) }
    assert_invalid("value") { client.name("a" * 255) }
    assert_invalid("value") { client.name("Onur\nOzturk") }
    assert_invalid("value") { client.name("Onur\u0000") }
    assert_invalid("value") { client.name("Onur\u007F") }
    assert_invalid("value") { client.name("\xFF\xFE".dup.force_encoding("UTF-8")) }
  end

  def test_value_limits_are_characters_not_bytes
    @stub.json(200, Fixtures.keyed("gender.200.dataset"))
    client.name("ş" * 254)
    assert_equal "ş" * 254, sent_json["value"]
  end

  def test_country
    assert_invalid("country") { client.name("Onur", country: "tr") }
    assert_invalid("country") { client.name("Onur", country: "TUR") }
    assert_invalid("country") { client.name("Onur", country: "") }
    assert_invalid("country") { client.name("Onur", country: :TR) }
  end

  def test_ai_mode
    assert_invalid("options.ai_mode") { client.name("Onur", ai_mode: "sometimes") }
    assert_invalid("options.ai_mode") { client.name("Onur", ai_mode: true) }
  end

  def test_force_to_genderize
    assert_invalid("forceToGenderize") { client.name("Onur", force_to_genderize: "yes") }
    assert_invalid("forceToGenderize") { client.name("Onur", force_to_genderize: true, ai_mode: "off") }
    assert_invalid("forceToGenderize") { client.name("Onur", force_to_genderize: true, ai_mode: "always") }
  end

  def test_id
    assert_invalid("id") { client.name("Onur", id: "") }
    assert_invalid("id") { client.name("Onur", id: "x" * 65) }
    assert_invalid("id") { client.name("Onur", id: 7) }
  end

  def test_unknown_keyword_is_an_argument_error
    assert_raises(ArgumentError) { client.name("Onur", askToAI: true) }
    assert_equal 0, @stub.connections
  end

  def test_batch_size
    assert_invalid("items") { client.gender_batch([]) }
    assert_invalid("items") { client.gender_batch(nil) }
    assert_invalid("items") { client.gender_batch({ type: "name", value: "Onur" }) }
    assert_invalid("items") { client.gender_batch(Array.new(51) { { type: "name", value: "Onur" } }) }
  end

  def test_batch_of_fifty_is_sent
    @stub.json(200, { "data" => [], "meta" => {} })
    assert_raises(GenderAPI::InvalidResponseError) do
      client.gender_batch(Array.new(50) { |i| { type: "name", value: "Name #{i}" } })
    end
    assert_equal 50, sent_json["items"].size
  end

  def test_batch_items
    assert_invalid("items[1].value") { client.gender_batch([{ type: "name", value: "A" }, { type: "name", value: "" }]) }
    assert_invalid("items[0]") { client.gender_batch(["Onur"]) }
    assert_invalid("items[0]") { client.gender_batch([{ type: "name", value: "A", askToAI: true }]) }
    assert_invalid("items[0]") { client.gender_batch([{ type: "name", value: "A", "type" => "email" }]) }
    assert_invalid("items[0].options") { client.gender_batch([{ type: "name", value: "A", options: { foo: 1 } }]) }
    assert_invalid("items[0].options") do
      client.gender_batch([{ type: "name", value: "A", ai_mode: "off", options: { ai_mode: "off" } }])
    end
    assert_invalid("items[0].forceToGenderize") do
      client.gender_batch([{ type: "name", value: "A", forceToGenderize: true, options: { ai_mode: "off" } }])
    end
    assert_invalid("items[0].id") { client.gender_batch([{ type: "name", value: "A", id: "x" * 65 }]) }
  end

  def test_batch_ids_must_be_unique
    assert_invalid("items") do
      client.gender_batch([{ type: "name", value: "A", id: "1" }, { type: "name", value: "B", id: "1" }])
    end
  end

  def test_phone
    assert_invalid("number") { client.validate_phone("12") }
    assert_invalid("number") { client.validate_phone("+1 555 abc") }
    assert_invalid("number") { client.validate_phone("1" * 33) }
    assert_invalid("number") { client.validate_phone(nil) }
    assert_invalid("country") { client.validate_phone("555 0100") }
    assert_invalid("country") { client.validate_phone("555 0100", country: "us") }
  end

  def test_phone_with_plus_needs_no_country
    @stub.json(200, Fixtures.keyed("phone.200.phone"))
    client.validate_phone("+1 (555) 010-0100")
    assert_equal({ "number" => "+1 (555) 010-0100" }, sent_json)
  end
end
