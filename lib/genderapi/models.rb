# frozen_string_literal: true

module GenderAPI
  # Read-only wrapper around a parsed JSON object (string keys).
  #
  # Every field of the response is kept, including fields this version of the
  # library does not know about: use {#[]}, {#dig} or {#to_h} for them. Values are
  # exactly as returned by the API (nulls stay nil; confidence is never rescaled).
  class Model
    # @api private
    def self.fields(*names)
      names.each do |name|
        define_method(name) { @raw[name.to_s] }
      end
    end

    # @param raw [Hash] parsed JSON object
    def initialize(raw)
      @raw = raw.is_a?(Hash) ? raw : {}
    end

    # @param key [String, Symbol]
    def [](key)
      @raw[key.to_s]
    end

    def dig(*keys)
      @raw.dig(*keys.map { |k| k.is_a?(Symbol) ? k.to_s : k })
    end

    def key?(key)
      @raw.key?(key.to_s)
    end

    # @return [Hash] the original parsed JSON object (string keys)
    def to_h
      @raw
    end

    def ==(other)
      other.is_a?(self.class) && other.to_h == @raw
    end
    alias eql? ==

    def hash
      @raw.hash
    end

    def inspect
      "#<#{self.class.name} #{@raw.inspect}>"
    end

    private

    def model(key, klass)
      value = @raw[key]
      value.is_a?(Hash) ? klass.new(value) : nil
    end
  end

  # meta.access: how the request was authorised.
  class Access < Model
    # mode: "api_key", "ip_trial" or "unauthenticated"
    # reason: nil, "api_key_missing", "api_key_invalid" or "api_key_not_found"
    fields :mode, :reason

    def api_key?
      mode == "api_key"
    end

    def ip_trial?
      mode == "ip_trial"
    end
  end

  # meta.usage: billing of this operation.
  #
  # * billing_status "not_charged": charged_credits is 0.
  # * "confirmed": the net charge is known (a confirmed refund can make it 0).
  # * "unconfirmed": charged_credits and remaining_credits are nil; contact
  #   support with the request ID before retrying.
  #
  # remaining_credits is the balance at completion; it can be negative or nil.
  # resets_at, limit and period_seconds describe the IP trial (nil otherwise).
  class Usage < Model
    fields :billing_status, :charged_credits, :remaining_credits, :resets_at, :limit, :period_seconds

    def confirmed?
      billing_status == "confirmed"
    end

    def unconfirmed?
      billing_status == "unconfirmed"
    end

    def not_charged?
      billing_status == "not_charged"
    end
  end

  # meta.summary of a batch: total = succeeded + failed; succeeded = identified + unknown.
  class BatchSummary < Model
    fields :total, :succeeded, :identified, :unknown, :failed
  end

  # Response metadata.
  class Meta < Model
    fields :request_id, :duration_ms

    # @return [Access, nil]
    def access
      model("access", Access)
    end

    # @return [Usage, nil]
    def usage
      model("usage", Usage)
    end

    # @return [BatchSummary, nil] present on batch responses
    def summary
      model("summary", BatchSummary)
    end
  end

  # A gender inference. It is an inference, not verification of identity, and it
  # can be unknown (gender nil). An unknown result is a successful, billed outcome.
  #
  # * result_status: "identified" or "unknown"
  # * reason: nil, "not_found", "no_name_candidate", "ambiguous" or "insufficient_evidence"
  # * confidence: 0..1 or nil. Not a calibrated probability; interpret it with confidence_kind
  #   ("observed_frequency" for dataset results, "model_reported" for AI results).
  # * sample_count: dataset sample count, nil for AI
  # * source: "dataset", "ai" or "none"
  # * country_source: nil, "dataset" or "ai_association" (never nationality or residence)
  # * match: {"name", "method", "scope", "country"} (see {#match})
  class Prediction < Model
    fields :input, :name, :gender, :country, :confidence, :confidence_kind, :sample_count,
           :source, :result_status, :reason, :country_source, :match

    def identified?
      result_status == "identified"
    end

    def unknown?
      result_status == "unknown"
    end
  end

  # Problem details for a single failed batch item.
  class ItemError < Model
    fields :type, :title, :status, :detail, :instance, :code, :request_id, :documentation, :action, :errors
  end

  # One row of a batch response. Exactly one of {#data} or {#error} is present.
  class BatchItem < Model
    fields :index, :id, :charged_credits

    # @return [Prediction, nil]
    def data
      model("data", Prediction)
    end

    # @return [ItemError, nil]
    def error
      model("error", ItemError)
    end

    def success?
      @raw.key?("data") && !@raw.key?("error")
    end

    def failed?
      @raw.key?("error")
    end
  end

  # Base class for every successful response: {"data" => ..., "meta" => {...}}.
  class Result < Model
    # @return [Meta]
    def meta
      Meta.new(@raw["meta"])
    end

    # @return [Usage, nil]
    def usage
      meta.usage
    end

    # @return [Access, nil]
    def access
      meta.access
    end

    # @return [String, nil]
    def request_id
      meta.request_id
    end

    # @return [Object] raw "data" value
    def data
      @raw["data"]
    end
  end

  # Result of {Client#gender}, {Client#name}, {Client#email} and {Client#username}.
  class GenderResult < Result
    # @return [Prediction]
    def data
      Prediction.new(@raw["data"])
    end
    alias prediction data
  end

  # Result of {Client#gender_batch}. HTTP 200 can contain failed items; they
  # are not raised. Retry only failed items, and only after billing is confirmed:
  # resubmitting successful items charges them again.
  class BatchResult < Result
    # @return [Array<BatchItem>] in submission order
    def data
      Array(@raw["data"]).map { |row| BatchItem.new(row) }
    end
    alias items data

    # @return [Array<BatchItem>]
    def succeeded_items
      items.select(&:success?)
    end

    # @return [Array<BatchItem>]
    def failed_items
      items.select(&:failed?)
    end

    def partial_failure?
      !failed_items.empty?
    end

    # @return [BatchSummary, nil]
    def summary
      meta.summary
    end
  end

  # Data of GET /usage (free): remaining_credits, expires_at, resets_at, limit, period_seconds.
  class UsageData < Model
    fields :remaining_credits, :expires_at, :resets_at, :limit, :period_seconds
  end

  # Result of {Client#usage}.
  class UsageResult < Result
    # @return [UsageData]
    def data
      UsageData.new(@raw["data"])
    end
  end

  # Data of POST /phone/validate. Checks number structure, not subscriber existence.
  class PhoneValidation < Model
    fields :valid, :possible, :e164, :country, :country_calling_code

    def valid?
      valid == true
    end

    def possible?
      possible == true
    end
  end

  # Result of {Client#validate_phone}.
  class PhoneResult < Result
    # @return [PhoneValidation]
    def data
      PhoneValidation.new(@raw["data"])
    end
  end
end
