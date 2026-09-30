# frozen_string_literal: true

require_relative "lib/genderapi/version"

Gem::Specification.new do |spec|
  spec.name          = "genderapi"
  spec.version       = GenderAPI::VERSION
  spec.authors       = ["Onur Ozturk"]
  spec.email         = ["support@genderapi.io"]

  spec.summary       = "Official GenderAPI.io V2 client for Ruby"
  spec.description   = "Official GenderAPI.io V2 client for Ruby. Infers gender from a name, email address " \
                       "or username (single or batch), reads credit usage and validates phone number structure. " \
                       "Results are inferences and can be unknown. Standard library only (net/http, json); " \
                       "no automatic retries or redirects. Version 2 is a breaking change from the 1.x (V1) client."
  spec.homepage      = "https://www.genderapi.io/api-documentation"
  spec.license       = "MIT"
  spec.metadata = {
    "homepage_uri" => "https://www.genderapi.io/api-documentation",
    "source_code_uri" => "https://github.com/GenderAPI/genderapi-ruby",
    "bug_tracker_uri" => "https://github.com/GenderAPI/genderapi-ruby/issues",
    "changelog_uri" => "https://github.com/GenderAPI/genderapi-ruby/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://www.genderapi.io/docs/v2/responses"
  }

  spec.required_ruby_version = ">= 3.0"

  # No runtime dependencies: net/http, json, openssl and uri ship with Ruby.
  spec.files         = Dir["lib/**/*.rb"] + %w[LICENSE README.md CHANGELOG.md]
  spec.require_paths = ["lib"]
end
