# frozen_string_literal: true

require_relative "test_helper"

class SafetyTest < StubTest
  def test_constructing_a_client_makes_no_request
    GenderAPI::Client.new(api_key: KEY, base_url: @stub.base_url)
    GenderAPI::Client.new(base_url: @stub.base_url)
    sleep 0.05
    assert_equal 0, @stub.connections
  end

  def test_redirect_is_not_followed
    @stub.enqueue(status: 302, headers: { "Location" => "#{@stub.base_url}/elsewhere", "X-Request-ID" => "r-1" },
                  body: "")
    @stub.json(200, Fixtures.keyed("gender.200.dataset"))
    error = assert_raises(GenderAPI::RedirectError) { client.name("Onur") }
    assert_equal 302, error.status
    assert_equal "#{@stub.base_url}/elsewhere", error.location
    assert_equal "r-1", error.request_id
    assert_equal 1, @stub.requests.size
    assert_equal ["/api/v2/gender"], @stub.requests.map(&:target)
  end

  def test_redirect_on_get_is_not_followed
    @stub.enqueue(status: 301, headers: { "Location" => "https://example.invalid/" }, body: "")
    assert_raises(GenderAPI::RedirectError) { client.usage }
    assert_equal 1, @stub.requests.size
  end

  def test_timeout_raises_and_does_not_retry
    @stub.enqueue(status: 200, headers: { "Content-Type" => "application/json" },
                  body: JSON.generate(Fixtures.keyed("gender.200.dataset")), delay: 1.5)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    error = assert_raises(GenderAPI::TimeoutError) { client(timeout: 0.3).name("Onur") }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_kind_of GenderAPI::TransportError, error
    assert_operator elapsed, :<, 1.4
    assert_includes error.message, "Do not retry automatically"
    assert_equal 1, @stub.connections
  end

  def test_default_timeout_is_ten_seconds
    assert_equal 10, GenderAPI::Client.new(api_key: KEY).timeout
  end

  def test_dropped_post_connection_is_not_retried
    @stub.enqueue(:close)
    @stub.json(200, Fixtures.keyed("gender.200.dataset"))
    assert_raises(GenderAPI::TransportError) { client.name("Onur") }
    sleep 0.05
    assert_equal 1, @stub.connections
  end

  def test_dropped_get_connection_is_not_retried
    # Net::HTTP retries idempotent requests once by default; the client disables it.
    @stub.enqueue(:close)
    @stub.json(200, Fixtures.keyed("usage.200.usage"))
    assert_raises(GenderAPI::TransportError) { client.usage }
    sleep 0.05
    assert_equal 1, @stub.connections
  end

  def test_connection_refused_is_a_transport_error
    port = @stub.port
    @stub.stop
    c = GenderAPI::Client.new(api_key: KEY, base_url: "http://127.0.0.1:#{port}/api/v2", timeout: 1)
    error = assert_raises(GenderAPI::TransportError) { c.name("Onur") }
    refute_includes error.message, KEY
  end

  def test_https_is_required_except_for_local_test_hosts
    assert_equal "https://api.genderapi.io/api/v2", GenderAPI::Client.new.base_url
    assert_equal "https://example.test/api/v2", GenderAPI::Client.new(base_url: "https://example.test/api/v2/").base_url
    %w[http://localhost:8080/api/v2 http://127.0.0.1/api/v2 http://[::1]:9000/api/v2].each do |url|
      GenderAPI::Client.new(base_url: url)
    end
    ["http://api.genderapi.io/api/v2", "ftp://api.genderapi.io", "api.genderapi.io/api/v2",
     "https://user:pass@api.genderapi.io/api/v2", "https://api.genderapi.io/api/v2?key=x", "", 42].each do |url|
      error = assert_raises(GenderAPI::ValidationError, url.inspect) { GenderAPI::Client.new(base_url: url) }
      assert_equal "base_url", error.field
    end
  end

  def test_inspect_never_reveals_the_key
    c = GenderAPI::Client.new(api_key: KEY, base_url: @stub.base_url)
    refute_includes c.inspect, KEY
    refute_includes c.to_s, KEY
    assert_includes c.inspect, "[FILTERED]"
  end

  def test_key_is_only_in_the_authorization_header
    @stub.json(200, Fixtures.keyed("gender.200.dataset"))
    client.name("Onur")
    req = last_request
    refute_includes req.target, KEY
    refute_includes req.body, KEY
    assert_equal ["authorization"], req.headers.select { |_k, v| v.include?(KEY) }.keys
  end

  def test_invalid_key_characters_are_rejected_without_network
    ["abc\r\nX-Evil: 1", "key with space", "ключ", 123].each do |key|
      assert_raises(GenderAPI::ValidationError) { GenderAPI::Client.new(api_key: key, base_url: @stub.base_url) }
    end
    assert_equal 0, @stub.connections
  end

  def test_blank_key_means_no_key
    refute GenderAPI::Client.new(api_key: "  ").api_key?
  end

  def test_invalid_timeout_is_rejected
    [0, -1, "10", Float::INFINITY, nil].each do |t|
      assert_raises(GenderAPI::ValidationError) { GenderAPI::Client.new(timeout: t) }
    end
  end
end
