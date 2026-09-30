# Changelog

## 2.0.0 - 2026-09-30

### Breaking

- The client now targets the GenderAPI.io V2 API (`https://api.genderapi.io/api/v2`). 1.x (V1 API) stays available and installable indefinitely (`gem install genderapi -v "~> 1.0"`); no deprecation or shutdown is planned. The source stays on the `v1` branch.
- New interface: `GenderAPI::Client#gender(type, value, country:, ai_mode:, force_to_genderize:, id:)` with `#name`, `#email` and `#username`, plus `#gender_batch(items)`, `#usage`, `#validate_phone(number, country:)`, `#capabilities` and `#error_catalog`. The V1 methods (`get_gender_by_*` and `get_gender_by_*_bulk`) have been removed.
- Responses are V2 `data`/`meta` objects wrapped in typed readers (`GenderResult`, `BatchResult`, `UsageResult`, `PhoneResult`) that keep every field. `probability` is replaced by `confidence` (0-1) and `confidence_kind`; `used_credits` is replaced by `meta.usage.charged_credits`.
- HTTP errors raise `GenderAPI::APIError` subclasses exposing `status`, `code`, `action`, `detail`, `errors`, `request_id`, `retry_after` and `billing_status`, instead of a generic `RuntimeError`.
- Ruby >= 3.0 is required. The runtime dependencies on `httparty` and `json` have been removed; the gem uses only the standard library.

### Added

- `api_key` defaults to `ENV["GENDERAPI_API_KEY"]`. Without a key, the server applies the shared IP trial.
- Client-side validation that mirrors the V2 request schema. Invalid input raises `GenderAPI::ValidationError` without making a network request.
- Partial batch success is returned together with `failed_items` and `summary`. Batches where every item failed raise an error whose `items` holds the item outcomes.
- `UnexpectedAccessModeError` when a configured key is answered with IP-trial access.

### Safety

- No automatic retries (including on 429 and for GET requests), no redirects followed, a 10-second default timeout, HTTPS required (plain http only for localhost tests), no request when the gem is loaded or a client is constructed, and the key is never placed in a URL, logged or shown by `inspect`.
