# genderapi-ruby

> This Ruby package is a legacy V1 client for GenderAPI.io. Its methods, request fields and response examples use the V1 contract. Use the [V1 API documentation](https://www.genderapi.io/api-documentation/v1) for this package. For a new integration, see the [V2 documentation](https://www.genderapi.io/api-documentation). V2 uses a different request and response format; changing the base URL alone does not migrate this client. Results are inferences and may be unresolved. They do not verify a person's identity.

Official Ruby SDK for [GenderAPI.io](https://www.genderapi.io) — determine gender from **names**, **emails**, and **usernames** using AI.

---

Get your Free API Key: [https://app.genderapi.io](https://app.genderapi.io)

---

## 🚀 Installation

Add this line to your Gemfile:

```ruby
gem 'genderapi'
```

Then execute:

```bash
bundle install
```

Or install it manually:

```bash
gem install genderapi
```

---

## 📝 Usage

### 🔹 Get Gender by Name

```ruby
require 'genderapi'

api = GenderAPI::Client.new(api_key: "YOUR_API_KEY")

# Basic usage
result = api.get_gender_by_name(name: "Michael")
puts result

# With askToAI set to true
result = api.get_gender_by_name(name: "李雷", ask_to_ai: true)
puts result
```

---

### 🔹 Get Gender by Email

```ruby
result = api.get_gender_by_email(email: "michael.smith@example.com")
puts result

# With askToAI set to true
result = api.get_gender_by_email(email: "michael.smith@example.com", ask_to_ai: true)
puts result
```

---

### 🔹 Get Gender by Username

```ruby
result = api.get_gender_by_username(username: "michael_dev")
puts result

# With askToAI set to true
result = api.get_gender_by_username(username: "michael_dev", ask_to_ai: true)
puts result
```

---

### 🔹 Get Gender by Name (Bulk)

```ruby
bulk_data = [
  { name: "Andrea", country: "DE", id: "123" },
  { name: "andrea", country: "IT", id: "456" }
]

result = api.get_gender_by_name_bulk(data: bulk_data)
puts result
```

---

### 🔹 Get Gender by Email (Bulk)

```ruby
bulk_data = [
  { email: "john@example.com", country: "US", id: "abc123" },
  { email: "maria@domain.de", country: "DE", id: "def456" }
]

result = api.get_gender_by_email_bulk(data: bulk_data)
puts result
```

---

### 🔹 Get Gender by Username (Bulk)

```ruby
bulk_data = [
  { username: "johnwhite", country: "US", id: "u001" },
  { username: "maria2025", country: "DE", id: "u002" }
]

result = api.get_gender_by_username_bulk(data: bulk_data)
puts result
```

---

## 📥 API Parameters

All API methods accept parameters as keyword arguments. All fields are optional except the primary identifier (name, email, or username).

---

### Name Lookup

| Parameter          | Type     | Required | Description |
|--------------------|----------|----------|-------------|
| name               | String   | Yes      | Name to query. |
| country            | String   | No       | Two-letter country code (e.g. "US"). Helps narrow down gender detection results by region. |
| askToAI            | Boolean  | No       | Defaults to `false`. Enables the legacy AI option. Supported single lookups with this option use a 2-credit tariff. This does not guarantee higher accuracy or a resolved result. Ordinary lookups and batch requests follow their V1 billing rules; inspect the returned `used_credits` value. |
| forceToGenderize   | Boolean  | No       | Default is `false`. When `true`, allows interpretation of nickname-like or unconventional inputs where supported by this V1 method. A result may still be unresolved; the option does not verify identity. |

---

### Email Lookup

| Parameter | Type   | Required | Description |
|-----------|--------|----------|-------------|
| email     | String | Yes      | Email address to query. |
| country   | String | No       | Two-letter country code (e.g. "US"). Helps narrow down gender detection results by region. |
| askToAI   | Boolean | No      | Defaults to `false`. Enables the legacy AI option. Supported single lookups with this option use a 2-credit tariff. This does not guarantee higher accuracy or a resolved result. Ordinary lookups and batch requests follow their V1 billing rules; inspect the returned `used_credits` value. |

---

### Username Lookup

| Parameter          | Type     | Required | Description |
|--------------------|----------|----------|-------------|
| username           | String   | Yes      | Username to query. |
| country            | String   | No       | Two-letter country code (e.g. "US"). Helps narrow down gender detection results by region. |
| askToAI            | Boolean  | No       | Defaults to `false`. Enables the legacy AI option. Supported single lookups with this option use a 2-credit tariff. This does not guarantee higher accuracy or a resolved result. Ordinary lookups and batch requests follow their V1 billing rules; inspect the returned `used_credits` value. |
| forceToGenderize   | Boolean  | No       | Default is `false`. When `true`, allows interpretation of nickname-like or unconventional inputs where supported by this V1 method. A result may still be unresolved; the option does not verify identity. |

---

### Name Lookup (Bulk)

| Parameter          | Type     | Required | Description |
|--------------------|----------|----------|-------------|
| data               | Array<Hash> | Yes | Array of objects containing name, optional country, and optional id. Limit is 100 records per request. |

Each object in the data array may include:
- `name`: The name to analyze (required).
- `country`: Two-letter country code (optional).
- `id`: Custom identifier to correlate input/output (optional).

---

### Email Lookup (Bulk)

| Parameter          | Type     | Required | Description |
|--------------------|----------|----------|-------------|
| data               | Array<Hash> | Yes | Array of objects containing email, optional country, and optional id. Limit is 50 records per request. |

Each object in the data array may include:
- `email`: The email address to analyze (required).
- `country`: Two-letter country code (optional).
- `id`: Custom identifier to correlate input/output (optional).

---

### Username Lookup (Bulk)

| Parameter          | Type     | Required | Description |
|--------------------|----------|----------|-------------|
| data               | Array<Hash> | Yes | Array of objects containing username, optional country, and optional id. Limit is 50 records per request. |

Each object in the data array may include:
- `username`: The username to analyze (required).
- `country`: Two-letter country code (optional).
- `id`: Custom identifier to correlate input/output (optional).

---

## ✅ API Response

Example JSON response for all endpoints:

```json
{
  "status": true,
  "used_credits": 1,
  "remaining_credits": 4999,
  "expires": 1743659200,
  "q": "michael.smith@example.com",
  "name": "Michael",
  "gender": "male",
  "country": "US",
  "total_names": 325,
  "probability": 98,
  "duration": "4ms"
}
```

---

### Response Fields

| Field             | Type               | Description                                         |
|-------------------|--------------------|-----------------------------------------------------|
| status            | Boolean            | `true` or `false`. Check errors if false.           |
| used_credits      | Integer            | Credits used for this request.                      |
| remaining_credits | Integer            | Remaining credits on your package.                  |
| expires           | Integer (timestamp)| Package expiration date (in seconds).               |
| q                 | String             | Your input query (name, email, or username).        |
| name              | String             | Found name.                                         |
| gender            | Enum[String]       | `"male"`, `"female"`, or `"null"`.                  |
| country           | Enum[String]       | Most likely country (e.g. `"US"`, `"DE"`, etc.).    |
| total_names       | Integer            | Number of samples behind the prediction.            |
| probability       | Integer            | Likelihood percentage (50-100).                     |
| duration          | String             | Processing time (e.g. `"4ms"`).                     |

---

## ⚠️ Error Codes

When `status` is `false`, check the following error codes:

| errno | errmsg                      | Description                                                       |
|-------|-----------------------------|-------------------------------------------------------------------|
| 50    | access denied               | Unauthorized IP Address or Referrer. Check your access privileges. |
| 90    | invalid country code        | Check supported country codes. [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2) |
| 91    | name not set \|\| email not set | Missing `name` or `email` parameter on your request.         |
| 92    | too many names \|\| too many emails | Limit is 100 for names, 50 for emails in one request.     |
| 93    | limit reached               | The API key credit has been finished.                            |
| 94    | invalid or missing key      | The API key cannot be found.                                      |
| 99    | API key has expired         | Please renew your API key.                                       |

Example error response:

```json
{
  "status": false,
  "errno": 94,
  "errmsg": "invalid or missing key"
}
```

---

## 🔗 Live Test Pages

You can try live gender detection directly on GenderAPI.io:

- **Determine gender from a name:**  
  [www.genderapi.io](https://www.genderapi.io)

- **Determine gender from an email address:**  
  [https://www.genderapi.io/determine-gender-from-email](https://www.genderapi.io/determine-gender-from-email)

- **Determine gender from a username:**  
  [https://www.genderapi.io/determine-gender-from-username](https://www.genderapi.io/determine-gender-from-username)

---

## 📚 Detailed API Documentation

For the complete V1 API reference used by this package, visit:

[https://www.genderapi.io/api-documentation/v1](https://www.genderapi.io/api-documentation/v1)

For a new integration, use the V2 documentation instead (different request and response format; this client is not a V2 client):

[https://www.genderapi.io/api-documentation](https://www.genderapi.io/api-documentation)

---

## ⚖️ License

MIT License
