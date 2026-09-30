# frozen_string_literal: true

module GenderAPI
  # Client-side checks that mirror the V2 request schema where they are cheap
  # and certain. The API remains authoritative (e.g. email syntax and ISO
  # country membership are validated by the server and reported as HTTP 422).
  #
  # @api private
  module Validation
    TYPES = %w[name email username].freeze
    AI_MODES = %w[off fallback always].freeze
    MAX_VALUE_LENGTH = 254
    MAX_ID_LENGTH = 64
    MAX_BATCH_ITEMS = 50
    CONTROL_CHARS = /[\x00-\x1f\x7f]/.freeze
    # Like the schema pattern \S (ECMAScript \s includes Unicode spaces and U+FEFF).
    NON_SPACE = /[^[:space:]\u{FEFF}]/.freeze
    COUNTRY = /\A[A-Z]{2}\z/.freeze
    PHONE = /\A\+?[0-9 ()-]+\z/.freeze

    # Ruby-style and wire-style keys accepted for a batch item.
    ITEM_KEYS = {
      "type" => :type, "value" => :value, "country" => :country, "id" => :id,
      "ai_mode" => :ai_mode, "force_to_genderize" => :force_to_genderize,
      "forceToGenderize" => :force_to_genderize, "options" => :options
    }.freeze

    module_function

    # Build and validate the exact wire body for one prediction.
    # @return [Hash] string-keyed wire body
    def gender_item(type, value, country: nil, ai_mode: nil, force_to_genderize: nil, id: nil, field: nil)
      prefix = field ? "#{field}." : ""
      type = type.to_s if type.is_a?(Symbol)
      unless TYPES.include?(type)
        raise ValidationError.new("type must be one of: #{TYPES.join(', ')}", field: "#{prefix}type")
      end

      value = check_value(value, "#{prefix}value")
      ai_mode = ai_mode.to_s if ai_mode.is_a?(Symbol)
      unless ai_mode.nil? || AI_MODES.include?(ai_mode)
        raise ValidationError.new("ai_mode must be one of: #{AI_MODES.join(', ')}", field: "#{prefix}options.ai_mode")
      end
      unless force_to_genderize.nil? || force_to_genderize == true || force_to_genderize == false
        raise ValidationError.new("force_to_genderize must be true or false", field: "#{prefix}forceToGenderize")
      end
      if force_to_genderize == true && %w[off always].include?(ai_mode)
        raise ValidationError.new("force_to_genderize cannot be combined with ai_mode off or always",
                                  field: "#{prefix}forceToGenderize")
      end
      check_country(country, "#{prefix}country") unless country.nil?
      check_id(id, "#{prefix}id") unless id.nil?

      body = { "type" => type, "value" => value }
      body["country"] = country unless country.nil?
      body["id"] = id unless id.nil?
      body["forceToGenderize"] = true if force_to_genderize == true
      body["options"] = { "ai_mode" => ai_mode } unless ai_mode.nil?
      body
    end

    # Normalise and validate a batch.
    # @return [Array<Hash>] string-keyed wire items
    def batch_items(items)
      unless items.is_a?(Array) && items.length.between?(1, MAX_BATCH_ITEMS)
        raise ValidationError.new("items must be an Array of 1-#{MAX_BATCH_ITEMS} items; split larger jobs yourself",
                                  field: "items")
      end

      wire = items.each_with_index.map { |item, index| batch_item(item, "items[#{index}]") }
      ids = wire.map { |w| w["id"] }.compact
      raise ValidationError.new("batch item ids must be unique", field: "items") if ids.uniq.length != ids.length

      wire
    end

    def batch_item(item, field)
      raise ValidationError.new("each batch item must be a Hash", field: field) unless item.is_a?(Hash)

      args = {}
      item.each do |key, val|
        name = ITEM_KEYS[key.to_s]
        raise ValidationError.new("unsupported batch item field #{key.to_s.inspect}", field: field) if name.nil?
        if args.key?(name)
          raise ValidationError.new("batch item field #{key.to_s.inspect} is given twice", field: field)
        end

        args[name] = val
      end
      if args.key?(:options)
        options = args.delete(:options)
        unless options.is_a?(Hash) && options.keys.map(&:to_s) - ["ai_mode"] == []
          raise ValidationError.new("options may only contain ai_mode", field: "#{field}.options")
        end
        if args.key?(:ai_mode)
          raise ValidationError.new("give ai_mode either at top level or in options", field: "#{field}.options")
        end

        args[:ai_mode] = options["ai_mode"] || options[:ai_mode]
      end
      gender_item(args.delete(:type), args.delete(:value), **args, field: field)
    end

    # @return [Hash] string-keyed wire body for phone validation
    def phone(number, country)
      unless number.is_a?(String) && number.length.between?(3, 32) && number.match?(PHONE)
        raise ValidationError.new("number must be 3-32 characters of digits, spaces, parentheses or hyphens, " \
                                  "optionally starting with +", field: "number")
      end
      if country.nil?
        unless number.start_with?("+")
          raise ValidationError.new("country is required unless number starts with +", field: "country")
        end
      else
        check_country(country, "country")
      end
      body = { "number" => number }
      body["country"] = country unless country.nil?
      body
    end

    def check_value(value, field)
      unless value.is_a?(String)
        raise ValidationError.new("value must be a String", field: field)
      end

      value = if value.encoding == Encoding::BINARY
                value.dup.force_encoding(Encoding::UTF_8)
              elsif value.encoding != Encoding::UTF_8
                value.encode(Encoding::UTF_8)
              else
                value
              end
      raise ValidationError.new("value must be valid UTF-8 text", field: field) unless value.valid_encoding?
      if !value.match?(NON_SPACE) || value.length > MAX_VALUE_LENGTH || value.match?(CONTROL_CHARS)
        raise ValidationError.new("value must contain 1-#{MAX_VALUE_LENGTH} characters, not only whitespace, " \
                                  "and no control characters", field: field)
      end

      value
    rescue EncodingError
      raise ValidationError.new("value must be valid UTF-8 text", field: field)
    end

    def check_country(country, field)
      return if country.is_a?(String) && country.match?(COUNTRY)

      raise ValidationError.new("country must be an uppercase ISO 3166-1 alpha-2 code such as \"US\"; " \
                                "omit it when unknown", field: field)
    end

    def check_id(id, field)
      return if id.is_a?(String) && id.length.between?(1, MAX_ID_LENGTH)

      raise ValidationError.new("id must be a String of 1-#{MAX_ID_LENGTH} characters", field: field)
    end
  end
end
