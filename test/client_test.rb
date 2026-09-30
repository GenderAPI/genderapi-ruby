# frozen_string_literal: true

require_relative "test_helper"

class ClientResponseTest < StubTest
  def test_single_dataset_success_and_headers
    @stub.json(200, Fixtures.keyed("gender.200.dataset"), "X-Request-ID" => "hdr-1")
    result = client.name("Onur", country: "TR", ai_mode: "off")

    req = last_request
    assert_equal "POST", req.method
    assert_equal "/api/v2/gender", req.target
    assert_equal "Bearer #{KEY}", req.headers["authorization"]
    assert_equal "application/json", req.headers["content-type"]
    assert_includes req.headers["accept"], "application/json"
    assert_match %r{\Agenderapi-ruby/2\.0\.0 }, req.headers["user-agent"]
    refute_includes req.target, KEY
    assert_equal({ "type" => "name", "value" => "Onur", "country" => "TR", "options" => { "ai_mode" => "off" } },
                 sent_json)

    assert_instance_of GenderAPI::GenderResult, result
    data = result.data
    assert_equal "male", data.gender
    assert_equal "identified", data.result_status
    assert data.identified?
    assert_nil data.reason
    assert_equal 0.9, data.confidence # unchanged, never a percentage
    assert_equal "observed_frequency", data.confidence_kind
    assert_equal 100, data.sample_count
    assert_equal "dataset", data.source
    assert_equal "dataset", data.country_source
    assert_equal({ "name" => "onur", "method" => "normalized", "scope" => "country", "country" => "TR" }, data.match)
    assert_equal "Onur", data.input["value"]

    usage = result.usage
    assert_equal "confirmed", usage.billing_status
    assert usage.confirmed?
    assert_equal 1, usage.charged_credits
    assert_equal 9, usage.remaining_credits
    assert_equal "api_key", result.access.mode
    assert_equal "11111111-1111-4111-8111-111111111111", result.request_id
    assert_equal Fixtures.keyed("gender.200.dataset"), result.to_h
  end

  def test_ai_alias_result_with_force_to_genderize
    @stub.json(200, Fixtures.keyed("gender.200.alias"))
    result = client.username("prenses", country: "TR", force_to_genderize: true)

    assert_equal({ "type" => "username", "value" => "prenses", "country" => "TR", "forceToGenderize" => true }, sent_json)
    data = result.data
    assert_equal "female", data.gender
    assert_nil data.name
    assert_equal "ai", data.source
    assert_equal "model_reported", data.confidence_kind
    assert_equal 0.7, data.confidence
    assert_nil data.sample_count
    assert_equal "ai_association", data.country_source
    assert_equal "model_inference", data.match["method"]
    assert_equal(-1, result.usage.remaining_credits) # balances can go negative
    assert_equal 2, result.usage.charged_credits
  end

  def test_unknown_result_is_success_not_error
    @stub.json(200, Fixtures.keyed("gender.200.unknown"))
    result = client.gender(:name, "zzzxxyy")

    assert_equal({ "type" => "name", "value" => "zzzxxyy" }, sent_json)
    data = result.data
    assert_nil data.gender
    assert data.unknown?
    assert_equal "not_found", data.reason
    assert_nil data.confidence
    assert_nil data.confidence_kind
    assert_equal "none", data.source
    assert_equal 1, result.usage.charged_credits
  end

  def test_email_sends_email_type_and_id
    @stub.json(200, Fixtures.keyed("gender.200.dataset"))
    client.email("alex@example.com", id: "row-7", ai_mode: :always)
    assert_equal({ "type" => "email", "value" => "alex@example.com", "id" => "row-7",
                   "options" => { "ai_mode" => "always" } }, sent_json)
  end

  def test_unknown_fields_are_tolerated_and_kept
    body = Fixtures.keyed("gender.200.dataset")
    body["data"]["future_field"] = { "x" => 1 }
    body["meta"]["future_meta"] = "yes"
    body["meta"]["usage"]["future_usage"] = 5
    body["top_level_extra"] = true
    @stub.json(200, body)
    result = client.name("Onur")

    assert_equal({ "x" => 1 }, result.data["future_field"])
    assert_equal({ "x" => 1 }, result.data[:future_field])
    assert_equal "yes", result.meta["future_meta"]
    assert_equal 5, result.usage["future_usage"]
    assert_equal true, result["top_level_extra"]
    assert_equal 1, result.dig(:data, :future_field, :x)
  end

  def test_without_key_uses_ip_trial_and_sends_no_authorization
    @stub.json(200, Fixtures.get("gender.200.dataset"))
    with_env(nil) do
      c = GenderAPI::Client.new(base_url: @stub.base_url)
      refute c.api_key?
      result = c.name("Onur", country: "TR")
      assert_equal "ip_trial", result.access.mode
      assert result.access.ip_trial?
      assert_equal "api_key_missing", result.access.reason
      assert_equal 10, result.usage.limit
      assert_equal 86_400, result.usage.period_seconds
      assert_equal "2026-09-26T12:00:00.000Z", result.usage.resets_at
    end
    assert_nil last_request.headers["authorization"]
  end

  def test_api_key_from_environment
    @stub.json(200, Fixtures.keyed("gender.200.dataset"))
    with_env("fedcba9876543210fedcba98") do
      GenderAPI::Client.new(base_url: @stub.base_url).name("Onur")
    end
    assert_equal "Bearer fedcba9876543210fedcba98", last_request.headers["authorization"]
  end

  def test_key_falling_back_to_ip_trial_raises_with_result
    @stub.json(200, Fixtures.get("gender.200.dataset").tap { |b| b["meta"]["access"]["reason"] = "api_key_invalid" })
    error = assert_raises(GenderAPI::UnexpectedAccessModeError) { client.name("Onur") }
    assert_equal "ip_trial", error.access_mode
    assert_equal "api_key_invalid", error.access_reason
    assert_equal "male", error.result.data.gender
    assert_equal 1, error.result.usage.charged_credits
    refute_includes error.message, KEY
    assert_equal 1, @stub.requests.size
  end

  def test_access_check_can_be_disabled
    @stub.json(200, Fixtures.get("gender.200.dataset"))
    result = client(require_api_key_access: false).name("Onur")
    assert_equal "ip_trial", result.access.mode
  end

  def test_batch_partial_success_is_returned
    @stub.json(200, Fixtures.keyed("gender_batch.200.batch"))
    items = [
      { type: "name", value: "Onur", country: "TR", id: "known" },
      { "type" => "name", "value" => "zzzxxyy", "id" => "missing", "options" => { "ai_mode" => "off" } },
      { type: :username, value: "prenses", id: "failed", ai_mode: "fallback", force_to_genderize: true }
    ]
    result = client.gender_batch(items)

    assert_equal "/api/v2/gender/batch", last_request.target
    assert_equal({ "items" => [
                   { "type" => "name", "value" => "Onur", "country" => "TR", "id" => "known" },
                   { "type" => "name", "value" => "zzzxxyy", "id" => "missing", "options" => { "ai_mode" => "off" } },
                   { "type" => "username", "value" => "prenses", "id" => "failed", "forceToGenderize" => true,
                     "options" => { "ai_mode" => "fallback" } }
                 ] }, sent_json)

    assert_instance_of GenderAPI::BatchResult, result
    assert result.partial_failure?
    assert_equal [0, 1, 2], result.items.map(&:index)
    assert_equal %w[known missing], result.succeeded_items.map(&:id)
    failed = result.failed_items
    assert_equal 1, failed.size
    assert_equal "failed", failed.first.id
    assert_nil failed.first.data
    assert_equal "ai_upstream_error", failed.first.error.code
    assert_equal "inspect_billing_before_retry", failed.first.error.action
    assert_equal 0, failed.first.charged_credits
    assert_equal "male", result.items[0].data.gender
    assert result.items[1].data.unknown?
    summary = result.summary
    assert_equal [3, 2, 1, 1, 1], [summary.total, summary.succeeded, summary.identified, summary.unknown, summary.failed]
    assert_equal 2, result.usage.charged_credits
  end

  def test_all_failed_batch_raises_with_item_data
    @stub.problem(502, Fixtures.keyed("gender_batch.502.batchFailed"))
    error = assert_raises(GenderAPI::ServerError) { client.gender_batch([{ type: "name", value: "Onur" }]) }
    assert_equal 502, error.status
    assert_equal "ai_upstream_error", error.code
    assert_equal "confirmed", error.billing_status
    assert_equal 1, error.items.size
    assert_equal "ai_upstream_error", error.items.first.error.code
    assert_equal 0, error.items.first.charged_credits
    assert_equal 1, error.data.size
    assert_equal 1, error.body["meta"]["summary"]["failed"]
  end

  def test_usage
    @stub.json(200, Fixtures.keyed("usage.200.usage"))
    result = client.usage
    req = last_request
    assert_equal "GET", req.method
    assert_equal "/api/v2/usage", req.target
    assert_nil req.body
    assert_nil req.headers["content-type"]
    assert_equal "Bearer #{KEY}", req.headers["authorization"]
    assert_equal 9, result.data.remaining_credits
    assert_equal "2026-09-26T12:00:00.000Z", result.data.expires_at
    assert result.usage.not_charged?
    assert_equal 0, result.usage.charged_credits
  end

  def test_validate_phone
    @stub.json(200, Fixtures.keyed("phone.200.phone"))
    result = client.validate_phone("555 0100", country: "US")
    assert_equal "/api/v2/phone/validate", last_request.target
    assert_equal({ "number" => "555 0100", "country" => "US" }, sent_json)
    refute result.data.valid?
    refute result.data.possible?
    assert_nil result.data.e164
    assert_equal 1, result.usage.charged_credits
  end

  def test_discovery_endpoints_send_no_key
    @stub.json(200, { "version" => "2.0.0", "limits" => { "batch_items" => 50 } })
    @stub.json(200, { "errors" => { "invalid_json" => { "code" => "invalid_json" } } })
    c = client
    assert_equal "2.0.0", c.capabilities["version"]
    assert_equal "/api/v2", last_request.target
    assert_nil last_request.headers["authorization"]
    assert_equal "invalid_json", c.error_catalog["errors"]["invalid_json"]["code"]
    assert_equal "/api/v2/errors", last_request.target
    assert_nil last_request.headers["authorization"]
  end

  private

  def with_env(value)
    old = ENV[GenderAPI::Client::ENV_API_KEY]
    value.nil? ? ENV.delete(GenderAPI::Client::ENV_API_KEY) : ENV[GenderAPI::Client::ENV_API_KEY] = value
    yield
  ensure
    old.nil? ? ENV.delete(GenderAPI::Client::ENV_API_KEY) : ENV[GenderAPI::Client::ENV_API_KEY] = old
  end
end
