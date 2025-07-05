require 'genderapi'

api = GenderAPI::Client.new(api_key: "YOUR_API_KEY")

result = api.get_gender_by_name(name: "Michael")
puts result
