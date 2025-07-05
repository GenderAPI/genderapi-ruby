# frozen_string_literal: true

require "httparty"
require "json"

module GenderAPI
  ##
  # Ruby SDK for GenderAPI.io
  #
  # This SDK allows determining gender from:
  #   - personal names
  #   - email addresses
  #   - social media usernames
  #
  # Supports advanced options like:
  #   - country filtering
  #   - direct AI queries
  #   - forced genderization for nicknames or unconventional strings
  #
  class Client
    include HTTParty
    base_uri "https://api.genderapi.io"

    ##
    # Initialize the GenderAPI client.
    #
    # @param api_key [String] Your API key as a Bearer token.
    # @param base_url [String] Optional API base URL. Defaults to https://api.genderapi.io
    #
    def initialize(api_key:, base_url: nil)
      @api_key = api_key
      self.class.base_uri(base_url) if base_url
      @headers = {
        "Authorization" => "Bearer #{@api_key}",
        "Content-Type" => "application/json"
      }
    end

    ##
    # Determine gender from a personal name.
    #
    # @param name [String] The name to analyze. (Required)
    # @param country [String, nil] Optional two-letter country code (e.g. "US").
    # @param ask_to_ai [Boolean] Whether to force AI lookup. Default: false
    # @param force_to_genderize [Boolean] Whether to analyze nicknames or emojis. Default: false
    #
    # @return [Hash] JSON response as a Ruby Hash.
    #
    def get_gender_by_name(name:, country: nil, ask_to_ai: false, force_to_genderize: false)
      payload = {
        name: name,
        country: country,
        askToAI: ask_to_ai,
        forceToGenderize: force_to_genderize
      }

      _post_request("/api", payload)
    end

    ##
    # Determine gender from an email address.
    #
    # @param email [String] The email to analyze. (Required)
    # @param country [String, nil] Optional two-letter country code (e.g. "US").
    # @param ask_to_ai [Boolean] Whether to force AI lookup. Default: false
    #
    # @return [Hash] JSON response as a Ruby Hash.
    #
    def get_gender_by_email(email:, country: nil, ask_to_ai: false)
      payload = {
        email: email,
        country: country,
        askToAI: ask_to_ai
      }

      _post_request("/api/email", payload)
    end

    ##
    # Determine gender from a social media username.
    #
    # @param username [String] The username to analyze. (Required)
    # @param country [String, nil] Optional two-letter country code (e.g. "US").
    # @param ask_to_ai [Boolean] Whether to force AI lookup. Default: false
    # @param force_to_genderize [Boolean] Whether to analyze nicknames or emojis. Default: false
    #
    # @return [Hash] JSON response as a Ruby Hash.
    #
    def get_gender_by_username(username:, country: nil, ask_to_ai: false, force_to_genderize: false)
      payload = {
        username: username,
        country: country,
        askToAI: ask_to_ai,
        forceToGenderize: force_to_genderize
      }

      _post_request("/api/username", payload)
    end

    private

    ##
    # Internal helper to send POST requests to the GenderAPI.io API.
    #
    # Handles:
    #   - Bearer authentication
    #   - Removal of nil values in payload
    #   - JSON parsing of responses
    #   - Raising errors for non-200 responses
    #
    # @param endpoint [String] API endpoint path (e.g. "/api")
    # @param payload [Hash] Request body data.
    #
    # @return [Hash] JSON response as Ruby Hash.
    #
    def _post_request(endpoint, payload)
      # Remove nil values from payload
      cleaned_payload = payload.reject { |_k, v| v.nil? }

      response = self.class.post(
        endpoint,
        headers: @headers,
        body: JSON.generate(cleaned_payload)
      )

      case response.code
      when 200
        parse_json(response.body)
      when 404
        # GenderAPI may return useful JSON for 404 too
        parse_json(response.body)
      else
        raise "GenderAPI Error: HTTP #{response.code} - #{response.body}"
      end
    rescue HTTParty::Error => e
      raise "GenderAPI Request failed: #{e.message}"
    rescue JSON::ParserError
      raise "GenderAPI Response is not valid JSON"
    end

    ##
    # Parse JSON response safely.
    #
    # @param body [String] JSON string.
    # @return [Hash] Parsed Hash.
    #
    def parse_json(body)
      JSON.parse(body)
    end
  end
end
