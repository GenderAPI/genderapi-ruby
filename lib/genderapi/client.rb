# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"
require "zlib"

module GenderAPI
  # Client for the GenderAPI.io V2 API (https://api.genderapi.io/api/v2).
  #
  # Server-side only: keep the API key in your server environment and never
  # embed it in browser or mobile code.
  #
  # Safety behaviour:
  # * No automatic retries, ever (a lost response may still have been billed),
  #   including on HTTP 429: {RateLimitError#retry_after} is exposed instead.
  # * Redirects are never followed; a 3xx raises {RedirectError}.
  # * Timeout defaults to 10 seconds for each connect, write and read operation.
  # * HTTPS only; plain http is accepted only for localhost/127.0.0.1/::1 (tests).
  # * Constructing a client makes no request. The API key is sent only in the
  #   Authorization header, never in a URL, and is never logged or inspected.
  #
  # Without an API key the server applies the shared IP trial (10 credits per
  # 24 hours per public IP, batches of at most 10 items). The client has no
  # trial logic of its own; the server decides.
  class Client
    DEFAULT_BASE_URL = "https://api.genderapi.io/api/v2"
    DEFAULT_TIMEOUT = 10
    ENV_API_KEY = "GENDERAPI_API_KEY"
    LOCAL_HOSTS = %w[localhost 127.0.0.1 ::1 [::1]].freeze
    ACCEPT = "application/json, application/problem+json"

    # @return [String] normalised base URL without trailing slash
    attr_reader :base_url
    # @return [Numeric] timeout in seconds for each connect, write and read operation
    attr_reader :timeout

    # @param api_key [String, nil] API key. Defaults to ENV["GENDERAPI_API_KEY"].
    #   Without a key the server applies the shared IP trial.
    # @param base_url [String] API base URL. Must be https, except for
    #   http://localhost, http://127.0.0.1 or http://[::1] (tests).
    # @param timeout [Numeric] seconds for each connect, write and read operation (default 10)
    # @param user_agent [String, nil] text appended to the default User-Agent
    # @param require_api_key_access [Boolean] when a key is configured, raise
    #   {UnexpectedAccessModeError} if a response reports IP-trial or
    #   unauthenticated access (the key was not accepted). Default true.
    def initialize(api_key: ENV.fetch(ENV_API_KEY, nil), base_url: DEFAULT_BASE_URL, timeout: DEFAULT_TIMEOUT,
                   user_agent: nil, require_api_key_access: true)
      @api_key = normalize_key(api_key)
      @base_url, @base_uri = normalize_base_url(base_url)
      unless timeout.is_a?(Numeric) && timeout.positive? && timeout.finite?
        raise ValidationError.new("timeout must be a positive number of seconds", field: "timeout")
      end

      @timeout = timeout
      if !user_agent.nil? && (!user_agent.is_a?(String) || user_agent.match?(/[\x00-\x1f\x7f]/))
        raise ValidationError.new("user_agent must be a String without control characters", field: "user_agent")
      end

      @user_agent = ["genderapi-ruby/#{VERSION}", "(Ruby #{RUBY_VERSION})", user_agent].compact.join(" ")
      @require_api_key_access = require_api_key_access ? true : false
    end

    # @return [Boolean] whether an API key is configured
    def api_key?
      !@api_key.nil?
    end

    # Never reveals the API key.
    def inspect
      "#<#{self.class.name} base_url=#{@base_url.inspect} timeout=#{@timeout} api_key=#{api_key? ? '[FILTERED]' : 'nil'}>"
    end
    alias to_s inspect

    # Predict gender for one name, email or username (POST /gender).
    #
    # Every call is a new, billable operation. Unknown results are successful
    # and billed. Single requests default to ai_mode "fallback" on the server
    # (1 credit total); "always" costs 2; force_to_genderize true costs 1 for a
    # dataset hit, otherwise 2 total.
    #
    # @param type [String, Symbol] "name", "email" or "username"
    # @param value [String] 1-254 characters, no control characters
    # @param country [String, nil] uppercase ISO 3166-1 alpha-2 code, e.g. "US"
    # @param ai_mode [String, Symbol, nil] "off", "fallback" or "always" (sent as options.ai_mode)
    # @param force_to_genderize [Boolean, nil] sent as forceToGenderize; not with ai_mode off/always
    # @param id [String, nil] optional 1-64 character correlation id
    # @return [GenderResult]
    def gender(type, value, country: nil, ai_mode: nil, force_to_genderize: nil, id: nil)
      body = Validation.gender_item(type, value, country: country, ai_mode: ai_mode,
                                                 force_to_genderize: force_to_genderize, id: id)
      request(:post, "/gender", body: body, auth: true) { |raw, ctx| check_prediction(raw, ctx) && GenderResult.new(raw) }
    end

    # @see #gender
    def name(value, **options)
      gender("name", value, **options)
    end

    # @see #gender
    def email(value, **options)
      gender("email", value, **options)
    end

    # @see #gender
    def username(value, **options)
      gender("username", value, **options)
    end

    # Predict 1-50 items in one request (POST /gender/batch). The server may
    # allow fewer (10 on the IP trial). Batch items default to ai_mode "off".
    #
    # Each item is a Hash with :type, :value and optional :country, :id,
    # :ai_mode and :force_to_genderize (wire names "forceToGenderize" and
    # "options" => {"ai_mode" => ...} are accepted too). Ids must be unique.
    #
    # Partial success is returned, not raised: inspect {BatchResult#failed_items}.
    # If every executed item fails the server answers with an error status and
    # an {APIError} is raised whose {APIError#items} holds the item outcomes.
    #
    # @param items [Array<Hash>]
    # @return [BatchResult]
    def gender_batch(items)
      wire = Validation.batch_items(items)
      request(:post, "/gender/batch", body: { "items" => wire }, auth: true) do |raw, ctx|
        check_batch(raw, ctx, wire) && BatchResult.new(raw)
      end
    end

    # Current balance and trial quota (GET /usage). Free.
    # @return [UsageResult]
    def usage
      request(:get, "/usage", auth: true) { |raw, ctx| check_envelope(raw, ctx) && UsageResult.new(raw) }
    end

    # Validate a phone number's structure (POST /phone/validate). Costs 1 credit,
    # including invalid numbers. It does not check subscriber existence.
    #
    # @param number [String] 3-32 characters: digits, spaces, parentheses, hyphens, optional leading +
    # @param country [String, nil] ISO alpha-2 code; required unless number starts with +
    # @return [PhoneResult]
    def validate_phone(number, country: nil)
      body = Validation.phone(number, country)
      request(:post, "/phone/validate", body: body, auth: true) { |raw, ctx| check_envelope(raw, ctx) && PhoneResult.new(raw) }
    end

    # Deployment version, limits and AI availability (GET /). No key is sent.
    # @return [Hash] parsed JSON
    def capabilities
      request(:get, "", auth: false) { |raw, _ctx| raw }
    end

    # Public machine-readable error catalog (GET /errors). No key is sent.
    # @return [Hash] parsed JSON ({"errors" => {code => {...}}})
    def error_catalog
      request(:get, "/errors", auth: false) { |raw, _ctx| raw }
    end

    private

    def normalize_key(key)
      return nil if key.nil?
      raise ValidationError.new("api_key must be a String", field: "api_key") unless key.is_a?(String)

      key = key.strip
      return nil if key.empty?
      if key.match?(/[\x00-\x20\x7f]/) || !key.ascii_only?
        raise ValidationError.new("api_key contains invalid characters", field: "api_key")
      end

      key
    end

    def normalize_base_url(url)
      raise ValidationError.new("base_url must be a String", field: "base_url") unless url.is_a?(String)

      uri = begin
        URI.parse(url.strip)
      rescue URI::InvalidURIError
        raise ValidationError.new("base_url is not a valid URL", field: "base_url")
      end
      unless uri.is_a?(URI::HTTP) && uri.host && !uri.host.empty? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
        raise ValidationError.new("base_url must be an absolute http(s) URL without credentials, query or fragment",
                                  field: "base_url")
      end
      if uri.scheme == "http" && !LOCAL_HOSTS.include?(uri.host.downcase)
        raise ValidationError.new("base_url must use https (plain http is only allowed for localhost tests)",
                                  field: "base_url")
      end

      uri.path = uri.path.sub(%r{/+\z}, "")
      [uri.to_s, uri]
    end

    def request(method, path, auth:, body: nil)
      uri = @base_uri.dup
      uri.path = "#{@base_uri.path}#{path}"
      uri.path = "/" if uri.path.empty?
      req = method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
      req["Accept"] = ACCEPT
      req["User-Agent"] = @user_agent
      req["Authorization"] = "Bearer #{@api_key}" if auth && @api_key
      if body
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body)
      end

      response = perform(uri, req)
      handle(response, auth: auth) { |raw, ctx| yield raw, ctx }
    end

    def perform(uri, req)
      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER if http.use_ssl?
      http.open_timeout = @timeout
      http.read_timeout = @timeout
      http.write_timeout = @timeout
      http.ssl_timeout = @timeout
      http.max_retries = 0 # Net::HTTP would otherwise retry idempotent requests once.
      http.start { |conn| conn.request(req) }
    rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, ::Timeout::Error => e
      raise TimeoutError.new(original: e)
    rescue SystemCallError, IOError, SocketError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse,
           Net::ProtocolError, EOFError, Zlib::Error => e
      raise TransportError.new(original: e)
    end

    def handle(response, auth:)
      status = response.code.to_i
      headers = response.each_header.to_h { |k, v| [k.downcase, v] }
      raw_body = response.body
      if status.between?(300, 399)
        raise RedirectError.new(status: status, headers: headers, raw_body: raw_body)
      end

      parsed = parse_json(raw_body, headers)
      if status >= 400
        raise GenderAPI.api_error_class(status).new(status: status, headers: headers, body: parsed, raw_body: raw_body)
      end
      unless status.between?(200, 299)
        raise InvalidResponseError.new("Unexpected HTTP #{status}; completion and billing are unknown.",
                                       status: status, headers: headers, raw_body: raw_body)
      end
      unless parsed.is_a?(Hash)
        raise InvalidResponseError.new("Expected a JSON object; completion and billing are unknown. " \
                                       "Check usage before another submission.",
                                       status: status, headers: headers, raw_body: raw_body)
      end

      ctx = { status: status, headers: headers, raw_body: raw_body }
      result = yield parsed, ctx
      check_access(result, ctx) if auth
      result
    end

    def parse_json(raw_body, headers)
      return nil if raw_body.nil? || raw_body.empty?
      return nil unless headers["content-type"].to_s.downcase.include?("json")

      text = raw_body.dup.force_encoding(Encoding::UTF_8)
      return nil unless text.valid_encoding?

      JSON.parse(text)
    rescue JSON::ParserError
      nil
    end

    def check_access(result, ctx)
      return unless @api_key && @require_api_key_access && result.is_a?(Result)

      mode = result.meta.access&.mode
      return if mode.nil? || mode == "api_key"

      raise UnexpectedAccessModeError.new(result: result, **ctx)
    end

    def invalid!(message, raw, ctx)
      raise InvalidResponseError.new("#{message} Keep the request ID and check usage before another submission.",
                                     body: raw, **ctx)
    end

    def check_envelope(raw, ctx)
      invalid!("Response is missing data.", raw, ctx) unless raw.key?("data")
      invalid!("Response is missing meta.", raw, ctx) unless raw["meta"].is_a?(Hash)
      true
    end

    def check_prediction(raw, ctx)
      check_envelope(raw, ctx)
      invalid!("Response data is not a prediction object.", raw, ctx) unless raw["data"].is_a?(Hash)
      true
    end

    # Structural checks only: every submitted item must come back once, in
    # order, with its id, and with exactly one of data or error.
    def check_batch(raw, ctx, wire)
      check_envelope(raw, ctx)
      rows = raw["data"]
      unless rows.is_a?(Array) && rows.length == wire.length
        invalid!("Batch result count does not match the submitted items.", raw, ctx)
      end

      rows.each_with_index do |row, index|
        unless row.is_a?(Hash) && row["index"] == index && row["id"] == wire[index]["id"]
          invalid!("Batch result mapping does not match the submitted items.", raw, ctx)
        end
        invalid!("Batch item must have exactly one of data or error.", raw, ctx) if row.key?("data") == row.key?("error")
      end
      true
    end
  end
end
