# frozen_string_literal: true

module GenderAPI
  # Base class for every error raised by this library.
  #
  # Error messages never contain the API key or the submitted input values.
  # The parsed body (+body+) can contain submitted inputs: inspect it securely
  # and do not log it wholesale.
  class Error < StandardError; end

  # Invalid client input or configuration. Raised before any network request.
  class ValidationError < Error
    # @return [String, nil] the offending argument or wire field, e.g. "value" or "items[2].country"
    attr_reader :field

    def initialize(message, field: nil)
      super(message)
      @field = field
    end
  end

  # No usable HTTP response (connection failure, TLS error, reset, timeout).
  # The request may still have completed and been billed; check {Client#usage}
  # before sending another prediction. The client never retries automatically.
  class TransportError < Error
    # @return [Exception, nil] the underlying low-level exception
    attr_reader :original

    def initialize(message = "Transport failed; completion and billing are unknown. Do not retry automatically.", original: nil)
      super(message)
      @original = original
    end
  end

  # The configured timeout elapsed while connecting, writing or reading.
  class TimeoutError < TransportError
    def initialize(message = "Request timed out; completion and billing are unknown. Do not retry automatically.", original: nil)
      super(message, original: original)
    end
  end

  # Shared readers for errors that carry an HTTP response.
  module ResponseContext
    # @return [Integer, nil] HTTP status
    attr_reader :status
    # @return [String, nil] meta.request_id, body request_id, or the X-Request-ID header
    attr_reader :request_id
    # @return [Integer, String, nil] Retry-After in seconds (Integer) or the raw header value (HTTP date)
    attr_reader :retry_after
    # @return [Hash, nil] parsed JSON body (string keys), when the body was a JSON object
    attr_reader :body
    # @return [String, nil] raw response body
    attr_reader :raw_body
    # @return [Hash{String=>String}] response headers with lower-case names
    attr_reader :headers

    private

    def assign_context(status:, body:, raw_body:, headers:)
      @status = status
      @body = body.is_a?(Hash) ? body : nil
      @raw_body = raw_body
      @headers = headers || {}
      meta = @body && @body["meta"].is_a?(Hash) ? @body["meta"] : {}
      @request_id = [meta["request_id"], @body && @body["request_id"], @headers["x-request-id"]]
                    .find { |v| v.is_a?(String) && !v.empty? }
      @retry_after = ResponseContext.parse_retry_after(@headers["retry-after"])
    end

    # @api private
    def self.parse_retry_after(value)
      return nil if value.nil? || value.strip.empty?

      value.strip.match?(/\A\d+\z/) ? value.strip.to_i : value.strip
    end
  end

  # The server answered with a redirect (3xx). Redirects are never followed so
  # the Bearer key is not forwarded to another location.
  class RedirectError < Error
    include ResponseContext

    # @return [String, nil] the Location header that was not followed
    attr_reader :location

    def initialize(status:, headers:, raw_body: nil)
      super("GenderAPI answered HTTP #{status} with a redirect; redirects are not followed. Check base_url.")
      assign_context(status: status, body: nil, raw_body: raw_body, headers: headers)
      @location = @headers["location"]
    end
  end

  # A 2xx response that is not the expected JSON structure. Billing is unknown:
  # keep {#request_id} and check {Client#usage} before another submission.
  class InvalidResponseError < Error
    include ResponseContext

    def initialize(message, status:, headers:, body: nil, raw_body: nil)
      super(message)
      assign_context(status: status, body: body, raw_body: raw_body, headers: headers)
    end
  end

  # An authenticated request was answered through IP-trial (or unauthenticated)
  # access, usually because the configured key is invalid or unknown. The request
  # has already run and may have consumed shared IP-trial credits; the full result
  # is available in {#result}. Disable with +require_api_key_access: false+.
  class UnexpectedAccessModeError < Error
    include ResponseContext

    # @return [GenderAPI::Result] the complete (already billed) result
    attr_reader :result

    # @return [String, nil] meta.access.mode, e.g. "ip_trial"
    attr_reader :access_mode

    # @return [String, nil] meta.access.reason, e.g. "api_key_invalid"
    attr_reader :access_reason

    def initialize(result:, status:, headers:, raw_body: nil)
      access = result.meta.access
      @access_mode = access&.mode
      @access_reason = access&.reason
      super("Expected API-key access but the response reports access mode #{@access_mode.inspect} " \
            "(#{@access_reason.inspect}). Check your API key; this request may have consumed IP-trial credits.")
      @result = result
      assign_context(status: status, body: result.to_h, raw_body: raw_body, headers: headers)
    end
  end

  # HTTP status >= 400. Exposes RFC 9457 Problem Details fields and the stable
  # machine-readable {#code}. Match on {#code}, never on {#detail} text.
  #
  # Proxy-level errors can be non-JSON; then {#code} is nil and {#raw_body} is set.
  class APIError < Error
    include ResponseContext

    # @return [String, nil] stable machine code, e.g. "insufficient_credits"
    attr_reader :code
    # @return [String, nil]
    attr_reader :title
    # @return [String, nil] human-readable detail (do not match on it)
    attr_reader :detail
    # @return [String, nil] problem type URI
    attr_reader :type
    # @return [String, nil] problem instance
    attr_reader :instance
    # @return [String, nil] recommended action, e.g. "wait_then_retry"
    attr_reader :action
    # @return [String, nil] link to the public error catalog
    attr_reader :documentation
    # @return [Array<Hash>] validation pointers: [{"pointer" => "/value", "message" => "..."}]
    attr_reader :errors
    # @return [GenderAPI::Usage, nil] meta.usage
    attr_reader :usage
    # @return [Array<GenderAPI::BatchItem>, nil] item outcomes of an all-failed batch (body "data")
    attr_reader :items

    def initialize(status:, headers:, body: nil, raw_body: nil)
      assign_context(status: status, body: body, raw_body: raw_body, headers: headers)
      b = @body || {}
      @code = str(b["code"])
      @title = str(b["title"])
      @detail = str(b["detail"])
      @type = str(b["type"])
      @instance = str(b["instance"])
      @action = str(b["action"])
      @documentation = str(b["documentation"])
      @errors = b["errors"].is_a?(Array) ? b["errors"] : []
      meta = b["meta"].is_a?(Hash) ? b["meta"] : {}
      @usage = meta["usage"].is_a?(Hash) ? Usage.new(meta["usage"]) : nil
      @items = b["data"].is_a?(Array) ? b["data"].select { |r| r.is_a?(Hash) }.map { |r| BatchItem.new(r) } : nil
      super(build_message)
    end

    # @return [String, nil] meta.usage.billing_status: "not_charged", "confirmed" or "unconfirmed"
    def billing_status
      @usage&.billing_status
    end

    # @return [Array<Hash>, nil] body "data" (all-failed batch rows) as raw hashes
    def data
      @body && @body["data"]
    end

    # True when the charge could not be confirmed; contact support with
    # {#request_id} instead of retrying.
    def billing_unconfirmed?
      billing_status == "unconfirmed"
    end

    private

    def str(value)
      value.is_a?(String) ? value : nil
    end

    def build_message
      parts = ["GenderAPI HTTP #{@status}"]
      parts << @code if @code
      parts << "action=#{@action}" if @action
      parts << "billing_status=#{billing_status}" if billing_status
      parts << "request_id=#{@request_id}" if @request_id
      parts.join(" ")
    end
  end

  # HTTP 400 (malformed request).
  class BadRequestError < APIError; end
  # HTTP 401 (invalid credentials).
  class AuthenticationError < APIError; end
  # HTTP 403 (access denied, disabled/expired key, insufficient credits).
  class PermissionDeniedError < APIError; end
  # HTTP 404.
  class NotFoundError < APIError; end
  # HTTP 422 (server-side validation, including the IP-trial batch limit). See {#errors}.
  class UnprocessableEntityError < APIError; end
  # HTTP 429. Wait {#retry_after} before another request; a retry is a new, billable operation.
  class RateLimitError < APIError; end
  # HTTP 5xx. Inspect {#billing_status} before sending another request.
  class ServerError < APIError; end

  # @api private
  def self.api_error_class(status)
    case status
    when 400 then BadRequestError
    when 401 then AuthenticationError
    when 403 then PermissionDeniedError
    when 404 then NotFoundError
    when 422 then UnprocessableEntityError
    when 429 then RateLimitError
    when 500..599 then ServerError
    else APIError
    end
  end
end
