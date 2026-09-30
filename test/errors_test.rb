# frozen_string_literal: true

require_relative "test_helper"

class ErrorResponseTest < StubTest
  def problem_body(status, code, action, extra = {})
    {
      "type" => "urn:genderapi:problem:#{code}", "title" => code.tr("_", " "), "status" => status,
      "detail" => "Synthetic #{code}.", "instance" => "urn:uuid:22222222-2222-4222-8222-222222222222",
      "code" => code, "request_id" => "22222222-2222-4222-8222-222222222222",
      "documentation" => "https://api.genderapi.io/api/v2/errors", "action" => action,
      "meta" => { "request_id" => "22222222-2222-4222-8222-222222222222", "duration_ms" => 3,
                  "access" => { "mode" => "api_key", "reason" => nil },
                  "usage" => { "charged_credits" => 0, "remaining_credits" => nil, "billing_status" => "not_charged",
                               "resets_at" => nil, "limit" => nil, "period_seconds" => nil } }
    }.merge(extra)
  end

  def test_401
    @stub.problem(401, problem_body(401, "invalid_api_key", "check_credentials"))
    error = assert_raises(GenderAPI::AuthenticationError) { client.name("Onur") }
    assert_kind_of GenderAPI::APIError, error
    assert_equal 401, error.status
    assert_equal "invalid_api_key", error.code
    assert_equal "check_credentials", error.action
    assert_equal "invalid api key", error.title
    assert_equal "Synthetic invalid_api_key.", error.detail
    assert_equal "22222222-2222-4222-8222-222222222222", error.request_id
    assert_equal "not_charged", error.billing_status
    refute_includes error.message, KEY
    refute_includes error.message, "Onur"
  end

  def test_403_insufficient_credits
    @stub.problem(403, Fixtures.keyed("gender.403.insufficient"))
    error = assert_raises(GenderAPI::PermissionDeniedError) { client.name("Onur") }
    assert_equal "insufficient_credits", error.code
    assert_equal "add_credits_or_wait_for_reset", error.action
    assert_equal 0, error.usage.remaining_credits
    assert_equal "not_charged", error.billing_status
    assert_equal "urn:genderapi:problem:insufficient_credits", error.type
  end

  def test_422_validation_pointers
    @stub.problem(422, Fixtures.keyed("gender.422.validation"))
    error = assert_raises(GenderAPI::UnprocessableEntityError) { client.email("not-an-email") }
    assert_equal "validation_error", error.code
    assert_equal [{ "pointer" => "/value", "message" => "Invalid email address." }], error.errors
    assert_nil error.usage.remaining_credits
  end

  def test_429_exposes_retry_after_and_does_not_retry
    @stub.problem(429, problem_body(429, "rate_limit_exceeded", "wait_then_retry"), "Retry-After" => "30")
    @stub.json(200, Fixtures.keyed("gender.200.dataset"))
    error = assert_raises(GenderAPI::RateLimitError) { client.name("Onur") }
    assert_equal 30, error.retry_after
    assert_equal "wait_then_retry", error.action
    assert_equal 1, @stub.requests.size
    assert_equal 1, @stub.connections
  end

  def test_retry_after_http_date_is_kept_as_string
    @stub.problem(429, problem_body(429, "concurrency_limit", "wait_then_retry"),
                  "Retry-After" => "Wed, 30 Sep 2026 12:00:00 GMT")
    error = assert_raises(GenderAPI::RateLimitError) { client.usage }
    assert_equal "Wed, 30 Sep 2026 12:00:00 GMT", error.retry_after
  end

  def test_502_non_json_proxy_error
    @stub.enqueue(status: 502, headers: { "Content-Type" => "text/html", "X-Request-ID" => "edge-9" },
                  body: "<html>Bad Gateway</html>")
    error = assert_raises(GenderAPI::ServerError) { client.name("Onur") }
    assert_equal 502, error.status
    assert_nil error.code
    assert_nil error.body
    assert_equal "<html>Bad Gateway</html>", error.raw_body
    assert_equal "edge-9", error.request_id
    assert_equal 1, @stub.requests.size
  end

  def test_503_unconfirmed_billing
    @stub.problem(503, Fixtures.keyed("gender.503.unconfirmed"), "X-Request-ID" => "header-id")
    error = assert_raises(GenderAPI::ServerError) { client.name("Onur") }
    assert_equal 503, error.status
    assert_equal "billing_reconciliation_required", error.code
    assert_equal "contact_support", error.action
    assert_equal "unconfirmed", error.billing_status
    assert error.billing_unconfirmed?
    assert_nil error.usage.charged_credits
    assert_nil error.usage.remaining_credits
    assert_equal "11111111-1111-4111-8111-111111111111", error.request_id # meta.request_id wins
    assert_includes error.message, "billing_status=unconfirmed"
    assert_equal 1, @stub.requests.size
  end

  def test_request_id_falls_back_to_body_then_header
    body = problem_body(500, "internal_error", "contact_support")
    body.delete("meta")
    @stub.problem(500, body, "X-Request-ID" => "header-id")
    error = assert_raises(GenderAPI::ServerError) { client.name("Onur") }
    assert_equal "22222222-2222-4222-8222-222222222222", error.request_id

    body.delete("request_id")
    @stub.problem(500, body, "X-Request-ID" => "header-id")
    error = assert_raises(GenderAPI::ServerError) { client.name("Onur") }
    assert_equal "header-id", error.request_id
    assert_nil error.billing_status
  end

  def test_invalid_json_success_is_an_error
    @stub.enqueue(status: 200, headers: { "Content-Type" => "application/json" }, body: "{not json")
    error = assert_raises(GenderAPI::InvalidResponseError) { client.name("Onur") }
    assert_equal 200, error.status
    assert_equal "{not json", error.raw_body
  end

  def test_non_object_json_is_an_error
    @stub.json(200, [1, 2])
    assert_raises(GenderAPI::InvalidResponseError) { client.name("Onur") }
  end

  def test_batch_mapping_mismatch_is_an_error
    body = Fixtures.keyed("gender_batch.200.batch")
    @stub.json(200, body)
    error = assert_raises(GenderAPI::InvalidResponseError) do
      client.gender_batch([{ type: "name", value: "Onur", id: "known" }])
    end
    assert_equal body, error.body
    assert_equal "11111111-1111-4111-8111-111111111111", error.request_id
  end
end
