# frozen_string_literal: true

# Official GenderAPI.io V2 client for Ruby.
#
# Requiring this file and constructing a client never makes a network request.
# Keep API keys on the server; never embed them in browser or mobile code.
require "genderapi/version"
require "genderapi/errors"
require "genderapi/models"
require "genderapi/validation"
require "genderapi/client"

module GenderAPI
end
