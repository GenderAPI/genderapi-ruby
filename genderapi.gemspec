# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "genderapi"
  spec.version       = "1.0.3"
  spec.authors       = ["Onur Ozturk"]
  spec.email         = ["support@genderapi.io"]

  spec.summary       = %q{Ruby SDK for GenderAPI.io — determine gender from names, emails, and usernames using AI.}
  spec.description   = %q{
    Official Ruby SDK for GenderAPI.io.

    This SDK allows determining gender from:
    - personal names
    - email addresses
    - social media usernames

    Supports:
    - country filtering
    - direct AI queries
    - forced genderization for nicknames or unconventional strings

    Built with HTTParty for easy HTTP handling.
  }
  spec.homepage      = "https://www.genderapi.io"
  spec.metadata = {
      "source_code_uri" => "https://github.com/GenderAPI/genderapi-ruby",
      "changelog_uri"   => "https://github.com/GenderAPI/genderapi-ruby/blob/main/CHANGELOG.md",
      "documentation_uri" => "https://rubydoc.info/gems/genderapi"
    }
  spec.license       = "MIT"

  # Gem dependencies
  spec.required_ruby_version = ">= 2.6"

  spec.add_dependency "httparty", "~> 0.18"
  spec.add_dependency "json", "~> 2.0"

  # Development dependencies
  spec.add_development_dependency "rspec", "~> 3.0"

  # Files to include in the gem
  spec.files         = Dir["lib/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]
end
