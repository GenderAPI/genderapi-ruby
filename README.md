# genderapi (Ruby)

Official GenderAPI.io V2 client for Ruby.

It sends names, email addresses and usernames to the [GenderAPI.io V2 API](https://www.genderapi.io/api-documentation) and returns the complete V2 response: the prediction in `data` and access and billing information in `meta`. Results are inferences, not identity verification, and they can be unknown.

> **Version 2.0.0 is a breaking release.** It targets the V2 API (`https://api.genderapi.io/api/v2`). 1.x (V1 API) stays available and installable indefinitely; no deprecation or shutdown is planned. To keep using it, pin 1.x with `gem install genderapi -v "~> 1.0"` (Gemfile: `gem "genderapi", "~> 1.0"`). The source stays on the [`v1` branch](https://github.com/GenderAPI/genderapi-ruby/tree/v1). See [Migrating from 1.x](#migrating-from-1x).

- Ruby >= 3.0
- No runtime dependencies (standard library `net/http` and `json`)
- **Server-side only.** Keep your API key in the server environment. Never embed it in browser, mobile or other client-side code.

## Installation

```ruby
# Gemfile
gem "genderapi", "~> 2.0"
```

```bash
bundle install
# or
gem install genderapi
```

## Quick start

```ruby
require "genderapi"

# Reads ENV["GENDERAPI_API_KEY"] when api_key is not given.
client = GenderAPI::Client.new(api_key: ENV["GENDERAPI_API_KEY"])

result = client.name("Andrea", country: "IT")
prediction = result.data

prediction.gender           # => "female", "male" or nil
prediction.result_status    # => "identified" or "unknown"
prediction.confidence       # => 0..1 or nil (not a calibrated probability)
prediction.confidence_kind  # => "observed_frequency", "model_reported" or nil
result.usage.charged_credits
result.usage.remaining_credits
result.request_id
```

Requiring the gem or constructing a client never makes a network request. Every method call makes exactly one HTTP request.

### Email and username

```ruby
client.email("alex.smith@example.com")
client.username("prenses", country: "TR", force_to_genderize: true)

# Generic form: type is "name", "email" or "username"
client.gender("username", "michael_dev", ai_mode: "off", id: "row-17")
```

### Batch (1-50 items)

```ruby
result = client.gender_batch([
  { type: "name", value: "Andrea", country: "IT", id: "a-1" },
  { type: "email", value: "alex@example.com", id: "a-2" },
  { type: "username", value: "prenses", id: "a-3", ai_mode: "fallback", force_to_genderize: true }
])

result.items.each do |item|
  if item.success?
    puts "#{item.id}: #{item.data.gender.inspect} (#{item.data.result_status})"
  else
    puts "#{item.id}: #{item.error.code} (#{item.error.action})"
  end
end

result.summary.to_h   # => {"total"=>3, "succeeded"=>2, "identified"=>1, "unknown"=>1, "failed"=>1}
result.failed_items   # failed rows; partial success is returned, not raised
```

The server may allow fewer items than 50 (IP-trial batches allow at most 10). Split larger jobs yourself. Item ids are optional, but when you give them they must be unique and at most 64 characters.

### Usage (free)

```ruby
usage = client.usage
usage.data.remaining_credits
usage.data.expires_at
usage.meta.access.mode   # "api_key", "ip_trial" or "unauthenticated"
```

### Phone validation

```ruby
client.validate_phone("+1 415 555 0100")
client.validate_phone("415 555 0100", country: "US") # country is required without a leading +
```

This checks the number's structure, not whether a subscriber exists. It costs 1 credit, including for invalid numbers.

### Discovery (no key sent)

```ruby
client.capabilities   # GET /api/v2
client.error_catalog  # GET /api/v2/errors
```

## Options

### Client

| Option | Default | Description |
| --- | --- | --- |
| `api_key` | `ENV["GENDERAPI_API_KEY"]` | Your API key. It is sent only as `Authorization: Bearer <key>`, never in a URL, and it is never logged or shown by `inspect`. |
| `base_url` | `https://api.genderapi.io/api/v2` | HTTPS is required. Plain `http://` is accepted only for `localhost`, `127.0.0.1` and `[::1]`, for tests. |
| `timeout` | `10` | Seconds allowed for each connect, write and read operation. |
| `user_agent` | `nil` | Text appended to the default `genderapi-ruby/2.0.0 (Ruby x.y.z)` User-Agent. |
| `require_api_key_access` | `true` | When a key is configured and the response reports IP-trial or unauthenticated access (the key was not accepted), raise `GenderAPI::UnexpectedAccessModeError`. The request has already been processed, so IP-trial credits may have been used. The complete result is in `error.result`, the mode in `error.access_mode`. Set `false` to return the result instead. Never applies without a key, or to `capabilities`/`error_catalog`. |

### Prediction (`gender`, `name`, `email`, `username`, batch items)

| Ruby argument | Wire field | Description |
| --- | --- | --- |
| `type` | `type` | `"name"`, `"email"` or `"username"` |
| `value` | `value` | 1-254 characters that are not all whitespace and contain no control characters |
| `country:` | `country` | Optional uppercase ISO 3166-1 alpha-2 code such as `"US"`. Leave it out when the country is unknown. |
| `ai_mode:` | `options.ai_mode` | `"off"`, `"fallback"` or `"always"`. If you leave it out, the server uses its default: `fallback` for single requests and `off` for batch items. |
| `force_to_genderize:` | `forceToGenderize` | `true` checks the dataset first (1 credit). If that result is unknown, it uses nickname-aware AI inference (2 credits total). It cannot be combined with `ai_mode` `off` or `always`. |
| `id:` | `id` | Optional correlation id, 1-64 characters |

Invalid input raises `GenderAPI::ValidationError` (with `#field`) **before** any network request. The API remains authoritative for email syntax and ISO country membership, and it reports problems with those as HTTP 422.

Credits (server rules): a dataset result or automatic AI fallback costs 1 credit, including unknown results. `ai_mode: "always"` costs 2. A request needs a positive starting balance, and the full tariff can take the balance below zero (for example, 1 - 2 = -1).

## Response fields

Every result wraps the parsed JSON. Typed readers are provided for the documented fields. `[]`, `dig` and `to_h` give access to all fields, including ones added in future API versions. Values are never converted: `confidence` stays on its 0-1 scale and is never turned into a percentage or probability.

| Reader | Meaning |
| --- | --- |
| `data.gender` | `"male"`, `"female"` or `nil` |
| `data.result_status` | `"identified"` (gender is set) or `"unknown"` (gender is nil). An unknown result is a successful, billed outcome. |
| `data.reason` | `nil`, `"not_found"`, `"no_name_candidate"`, `"ambiguous"` or `"insufficient_evidence"` |
| `data.confidence` / `data.confidence_kind` | Score from 0 to 1 and what it is: `observed_frequency` (dominant dataset count / total) or `model_reported` (AI score, not calibrated). Both are nil when gender is nil. |
| `data.sample_count` | Dataset sample count; nil for AI |
| `data.source` | `"dataset"`, `"ai"` or `"none"` |
| `data.name`, `data.country`, `data.country_source` | The returned name, the country and where the country came from (`dataset`, `ai_association` or nil). These fields never indicate nationality or residence. |
| `data.match` | `{"name", "method", "scope", "country"}`: the dataset candidate and lookup scope |
| `data.input` | The input as the server understood it |
| `meta.request_id`, `meta.duration_ms` | Identifier and duration of this HTTP attempt |
| `meta.access.mode` / `.reason` | `api_key`, `ip_trial` or `unauthenticated`; the trial reason, if any |
| `meta.usage.billing_status` | `not_charged`, `confirmed` or `unconfirmed` |
| `meta.usage.charged_credits` | Net charge. It is nil when billing is unconfirmed. |
| `meta.usage.remaining_credits` | Balance when the request completed. It can be negative, or nil if unknown. |
| `meta.usage.resets_at`, `.limit`, `.period_seconds` | IP-trial window (nil otherwise) |
| Batch `items[i].index`, `.id`, `.charged_credits` | Each row has exactly one of `.data` (Prediction) or `.error` (item problem) |
| Batch `meta.summary` | `total`, `succeeded`, `identified`, `unknown`, `failed` |

## Errors

All errors inherit from `GenderAPI::Error`. Messages never include your key or input values.

| Class | When |
| --- | --- |
| `ValidationError` | Invalid arguments. No request was sent. |
| `APIError` | HTTP >= 400. Subclasses: `BadRequestError` (400), `AuthenticationError` (401), `PermissionDeniedError` (403), `NotFoundError` (404), `UnprocessableEntityError` (422), `RateLimitError` (429), `ServerError` (5xx) |
| `RedirectError` | The server answered with a 3xx. Redirects are never followed, so your key is never forwarded to another location. |
| `TransportError` / `TimeoutError` | No usable response was received. The request may still have completed and been billed. |
| `InvalidResponseError` | A 2xx response that is not the expected JSON structure |
| `UnexpectedAccessModeError` | A key was configured, but the response reports IP-trial or unauthenticated access (see `require_api_key_access`). The request has already been processed and trial credits may have been used; the complete result is in `error.result`. Do not resend automatically. |

`APIError` exposes `status`, `code` (a stable machine code; match on this, never on `detail`), `title`, `detail`, `type`, `instance`, `action`, `documentation`, `errors` (validation pointers such as `[{"pointer" => "/value", "message" => "..."}]`), `request_id` (from `meta.request_id`, the body, or the `X-Request-ID` header), `retry_after` (from the `Retry-After` header: Integer seconds, or the raw String for an HTTP date), `usage`, `billing_status`, `billing_unconfirmed?`, `items` / `data` (item outcomes when every batch item failed), `body` (parsed) and `raw_body`. Proxy errors can be non-JSON. In that case `code` is nil and `raw_body` holds the response text. The error body can contain your inputs, so inspect it securely and do not log it wholesale.

```ruby
begin
  client.name("Andrea")
rescue GenderAPI::RateLimitError => e
  # Wait e.retry_after seconds. A later request is a new, billable operation.
rescue GenderAPI::APIError => e
  if e.billing_unconfirmed?
    # Contact support with e.request_id. Do not retry automatically.
  end
  warn "GenderAPI #{e.status} #{e.code} #{e.action} #{e.request_id}"
rescue GenderAPI::TransportError => e
  # The outcome is unknown. Check client.usage before sending again.
end
```

The machine-readable catalog of codes and actions is at [`/api/v2/errors`](https://api.genderapi.io/api/v2/errors) (`client.error_catalog`).

## Billing and no-retry rules

- **No automatic retries, ever.** Every prediction or phone request is a new, billable operation. If a response is lost, the request may still have been billed, so the client never retries, not even on 429.
- **429:** wait for `retry_after` before sending another request. That request is a new operation with normal charges.
- **`billing_status: "unconfirmed"`** (for example `billing_reconciliation_required`): contact support with the `request_id` before retrying.
- **5xx prediction failures:** check `billing_status` and fix the cause before sending another request.
- **Partial batch success:** retry only the failed items, and only after billing is confirmed. Resubmitting successful items charges them again.
- **Timeouts or transport errors:** check `client.usage` before sending again.
- Redirects are never followed. HTTPS is required. The default timeout is 10 seconds.

## IP trial (no key)

The client also works without an API key. The server then applies a shared IP trial: 10 credits per 24 hours per public IP address, normal tariffs, and batches of at most 10 items. Clients behind the same public IP share this quota. `meta.access.mode` is `ip_trial`, and `meta.usage.resets_at` shows when the window resets. The client has no trial logic of its own; the server decides.

If you configure a key and the server does not accept it, the request can fall back to the IP trial. By default the client then raises `UnexpectedAccessModeError`. The request has already been processed and may have used IP-trial credits. Check your key.

## Migrating from 1.x

You do not have to migrate. 1.x (V1 API) stays available and installable indefinitely, with no deprecation or shutdown planned. To stay on it:

```bash
gem install genderapi -v "~> 1.0"
```

or in your Gemfile:

```ruby
gem "genderapi", "~> 1.0"
```

The 1.x source stays on the [`v1` branch](https://github.com/GenderAPI/genderapi-ruby/tree/v1).

V2 is a different request and response contract, so changing only the URL is not enough. Your API key and credit balance stay the same.

| 1.x (V1) | 2.x (V2) |
| --- | --- |
| `get_gender_by_name(name:)`, `get_gender_by_email(email:)`, `get_gender_by_username(username:)` | `client.name(value)`, `client.email(value)`, `client.username(value)` or `client.gender(type, value)` |
| V1 routes `/api`, `/api/email`, `/api/username` | `POST /api/v2/gender` with `type` and `value` |
| `get_gender_by_*_bulk(data:)` on `/api/*/multi/country` | `client.gender_batch(items)` -> `POST /api/v2/gender/batch` with `items` (1-50) |
| `ask_to_ai:` / `askToAI` | `ai_mode:` -> `options.ai_mode` (`off`, `fallback`, `always`). Single requests already default to `fallback`. |
| `force_to_genderize:` (name, username) | `force_to_genderize:` -> `forceToGenderize` for name, email and username; dataset first, then nickname-aware AI |
| Flat response fields (`q`, `name`, `gender`, ...) | `data` for the result and `meta` for access and billing |
| `probability` (percentage) | `data.confidence` (0-1) plus `data.confidence_kind`. AI scores are not calibrated probabilities. |
| `total_names` | `data.sample_count` (nullable) |
| `used_credits` / `remaining_credits` | `meta.usage.charged_credits` / `meta.usage.remaining_credits` |
| `expires` | `client.usage.data.expires_at` |
| `status: false` with `errno` / `errmsg` | HTTP status plus a Problem Details `code` and `action`, raised as `GenderAPI::APIError` |
| Generic `RuntimeError` on 5xx | Typed errors with `billing_status`, `request_id` and `retry_after` |
| HTTParty dependency | Standard library only |
| Ruby >= 2.6 | Ruby >= 3.0 |

## Documentation

- API documentation: https://www.genderapi.io/api-documentation
- V2 guides: [responses](https://www.genderapi.io/docs/v2/responses), [request parameters](https://www.genderapi.io/docs/v2/request-parameters), [AI options](https://www.genderapi.io/docs/v2/ai-options), [batch](https://www.genderapi.io/docs/v2/batch), [credits and usage](https://www.genderapi.io/docs/v2/credits-and-usage), [errors and retries](https://www.genderapi.io/docs/v2/errors-and-retries), [authentication](https://www.genderapi.io/docs/v2/authentication), [phone validation](https://www.genderapi.io/docs/v2/phone-validation), [migration](https://www.genderapi.io/docs/v2/migration)
- OpenAPI: https://api.genderapi.io/api/v2/openapi.json

## Development

```bash
bundle config set --local path vendor/bundle
bundle install
bundle exec rake test   # local stub server only: no real API, no credits
gem build genderapi.gemspec
```

Test fixtures in `test/fixtures/openapi_examples.json` are the response examples from the V2 OpenAPI document.

### Releasing

Pushing a `v*` tag (for example `v2.0.0`) runs `.github/workflows/publish.yml`. The workflow tests the gem, checks that the tag matches `GenderAPI::VERSION`, builds it and pushes it to RubyGems. It authenticates through RubyGems trusted publishing (OIDC) configured for this repository and workflow, so no API key is stored.

## License

MIT
