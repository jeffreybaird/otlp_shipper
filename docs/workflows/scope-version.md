# Dynamic instrumentation scope version

## Scope and ownership

Fix the logs/metrics scope version reported to the hub: use the loaded
`otlp_shipper` application version instead of `0.1.0`. Preserve original trace
scopes. Keep conformance checks aligned with the emitted version. No package
publication, consumer upgrade, deployment, or historical log rewrite is included.

Base: `7ae6684`; branch: `codex/dynamic-scope-version`.
Primary agent owns integration and this record; spec writer owns new regression
and acceptance tests/config registration; implementer owns encoder/conformance
production changes; independent runner uses gpt-5.6-luna; independent reviewer
owns final review. No dependency or public API changes intended.

## Acceptance and checks

Decode logs and metrics and compare scope version to OTP application metadata.
Conformance accepts the current scope version and rejects stale values. Existing
trace identity tests remain passing. Execute focused regression tests, strict
CucumberEx, formatting, compile warnings-as-errors, full ExUnit, Credo and Dialyzer.

## Verification evidence

Red verified on base `7ae6684dcf354918ca356d4eeed3931b0a85bf4c`, tracked diff
SHA256 `7291c96bb8ecd4fe44e1f81e20cdf76d2f73099f58184ccde21bb017afd967eb`.
Environment: Elixir 1.19.5 (compiled OTP 28), OTP 29 / ERTS 17.0.1.

- `mix test test/otlp_shipper/scope_version_test.exs`: exit 2, 5 tests,
  4 assertion failures. Logs/metrics emitted `0.1.0` versus installed `0.2.0`;
  current-version conformance failed and stale-version conformance passed.
- `MIX_ENV=test mix cucumber`: exit 1, 42 scenarios, 39 passed, 3 failed:
  SCOPE-01 logs, SCOPE-01 metrics, SCOPE-03 current conformance.
- Initial sandbox Mix socket `:eperm` resolved with escalation; assertion runs
  above used successful escalated execution.

New regression inputs at red (SHA256):

| File | Digest |
| --- | --- |
| `docs/features/scope-version.feature` | `eb18b85d459241184e5bbefe3ef43ae34c18b000d860fd7ff89cedcec6e7bb79` |
| `features/step_definitions/scope_version_steps.ex` | `a2875b097fbcfac8ddb380dde3e10905aed6d7274ee02a67b2b853ae81484dc4` |
| `test/otlp_shipper/scope_version_test.exs` | `033058bd331d2d50805c9235f6dfd409d14727dbc1b879490d0a66e90036980a` |
| `test/support/conformance_fixtures.ex` | `a21a6947a25035dedb4af981f30121e5ec765ec82e536dda5aaa89fe4623394a` |

## Scenario mapping

All scenarios execute in `docs/features/scope-version.feature`, with steps in
`features/step_definitions/scope_version_steps.ex` and focused ExUnit coverage
in `test/otlp_shipper/scope_version_test.exs`:

- SCOPE-01: decoded logs and metrics identify installed application version.
- SCOPE-02: original trace scope name/version preserved.
- SCOPE-03: conformance accepts current shipper version.
- SCOPE-04: conformance rejects stale, incorrect, and prefix-matching versions.

Historical Collector captures remain byte-for-byte unchanged. Test-only fixture
adaptation changes the shipper scope version at runtime; all recorded payload
assertions remain intact. This reflects the user-authorized version correction.

## Green verification

Independent runner (gpt-5.6-luna), same toolchain, tracked diff SHA256
`c6fb2bc7611b780e576d2138703533dab28e02a93fbd8a9ff2d1d467d6e3eaef`.
All new code/test input hashes match the red inputs above. This work record alone
was subsequently updated with results.

| Command | Result |
| --- | --- |
| `mix test test/otlp_shipper/scope_version_test.exs` | exit 0; 5 tests, 0 failures |
| `mix format --check-formatted` | exit 0 |
| `mix compile --warnings-as-errors` | exit 0 |
| `mix test` | exit 0; 22 doctests, 171 tests, 0 failures |
| `MIX_ENV=test mix cucumber` | exit 0; 42 scenarios passed |
| `mix credo --strict` | exit 0; no issues |
| `mix dialyzer` | exit 0; zero errors/skips |

## Review and delivery

Independent preliminary review found no actionable code or coverage issues.
Final commit review and CI status are reported in the PR. Real Docker Collector
and packaged consumer smokes were not run for this focused change; no new release
was published. The hub already displays the received scope version. Consumers
must upgrade to a release containing the fix for new telemetry to report the
correct version; existing records keep their original reported version.

## Human approvals

None required beyond the user request. Sandbox escalation permits repository writes.
