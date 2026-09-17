# Phase 4: SDK-compatible trace export

Status: Phase 4 merged in PR #16 on September 17, 2026, with all CI checks passing. This record
does not make trace export available in version 0.1.1. Implementation belongs to
Phases 5–7.

## Supported boundary

The initial supported pair is exactly `opentelemetry` 1.7.0 and
`opentelemetry_api` 1.5.0. Minimum and current supported pairs are the same until
another pair passes these probes. A broad Mix requirement does not establish SDK
record compatibility. Initialization must reject an unverified SDK/API pair instead
of decoding it using assumed record layouts. The current official Hex releases were checked September 17,
2026: [SDK](https://hex.pm/packages/opentelemetry),
[API](https://hex.pm/packages/opentelemetry_api), and
[Finch instrumentation](https://hex.pm/packages/opentelemetry_finch).

The existing SDK owns context propagation, sampling, span creation, and batch
scheduling. The planned exporter consumes each batch synchronously; it does not
retain its ETS table, introduce another pending-span queue, or install SDK
configuration into the consuming application. Only the batch processor is targeted.

### Optional compilation

Select a compile-time guarded SDK adapter module: define it only when
`Code.ensure_loaded?(:otel_exporter_traces)` is true. Keep shared logs/metrics
modules independent of that guard and SDK includes. SDK-specific record extraction
stays inside the guarded adapter/conversion boundary. A consumer adding the SDK
later must recompile the shipper dependency; hot-loading an SDK into an already
compiled non-tracing release does not enable tracing.

`sh scripts/trace_consumer_smoke.sh` passed for fresh SDK-present and SDK-absent
production releases. Its fixture adapter declares the SDK as an optional dependency,
which supplies a Mix compilation-order edge when the consumer supplies the SDK.
Phase 6 must change the package SDK declaration from test-only to optional when
introducing the real guarded adapter. A test-only dependency alone is insufficient.
The fixture validates adapter presence/absence in the release, exact SDK/API
versions, callback initialization, and absence of the canonical exporter.

This proves the selected compilation mechanism, not a finished adapter.
`scripts/package_smoke.sh` also passed: a fresh packaged consumer compiled, released,
and delivered logs and metrics without the optional tracing API or runtime gpb.
Phase 6 must repeat both proofs with the implemented adapter. The current package's
SDK dependency remains test-only during this probe-only phase.

## Ownership and cancellation

The consumer owns a supervisor whose children start in this order: named Finch
pool through the existing `OtlpShipper.Pool` startup boundary, then named SDK
provider/processor. Use `:rest_for_one` so a pool failure
restarts the dependent provider. A brutally killed Finch supervisor can leave
registered descendants briefly alive; the shared pool boundary bounds that restart
race to one second. Raw Finch startup without that boundary failed the crash probe.
Reverse shutdown stops the provider before Finch.
Every instance supplies distinct provider, batch processor, and pool names. The
exporter receives a pool reference; it neither starts a global pool in `init/1`
nor relies on `shutdown/1` to destroy it. Invalid or unavailable pool references
make initialization return `:ignore` with a bounded diagnostic.

The SDK's provider supervisor supports explicit resource and processor options.
A named provider still needs an explicit batch-processor name; otherwise the
single-processor default uses the global batch name. Probe code avoids the global
tracer cache by requesting a tracer directly from the named provider.

The SDK hands table ownership to the export worker and deletes the table after the
callback returns, regardless of the callback result. The SDK can kill that worker
at its export timeout. All adapter work must therefore run in that worker or in
linked work owned by its supervised lifecycle. No detached conversion or retry
process may outlive cancellation. An HTTP request already sent may still be
processed remotely after cancellation.

`force_flush` returns after sending a cast; it does not acknowledge delivery.
The processor's termination path may export remaining data without invoking the
exporter's shutdown callback. Returning `:failed_retryable` does not make this
batch processor requeue a batch. See the executable TCP scenarios for observed
process and table boundaries.

## Resource and span fidelity

Use the resource supplied to `export/3` as authoritative. A missing or malformed
resource is a permanent batch error; do not substitute shipper defaults. An empty
valid SDK resource remains valid. Use SDK accessors for attributes and schema URL.
Resource/scope identity is never truncated to fit a request.

| Input | Planned conversion |
| --- | --- |
| Span trace/span/parent IDs | Validate nonzero 128/64-bit identities; encode fixed-width big-endian bytes; absent parent is empty |
| Trace state | Preserve SDK members and ordering using the protocol representation |
| Span name/kind/status | Preserve supported values; reject malformed spans rather than fabricate meaning |
| Span and event timestamps | Native monotonic time plus clock offset, converted to epoch nanoseconds |
| Attributes | Preserve supported SDK scalar/array values; reject unsupported values instead of using generic stringification |
| Dropped counts | Read `otel_attributes:dropped/1`, `otel_events:dropped/1`, and `otel_links:dropped/1` |
| Events | Preserve order, timestamp, name, attributes, and dropped counts |
| Links | Preserve IDs, trace state, attributes, and dropped attributes |
| Scope | Preserve name, version, schema URL; group spans by original scope |
| Resource | Preserve callback attributes and schema URL; never call logs/metrics `Resource.new/2` |

SDK 1.7.0 exposes `parent_span_is_remote` and span trace flags. Link records expose
neither trace flags nor remote-context state; those unavailable fields must not be
invented. API 1.5.0 scope records have no attributes or dropped-attribute count.
Document that fidelity limit rather than claiming all OTLP fields are supported.

Capture time offset at the adapter boundary and pass it to pure conversion. Compare
against `opentelemetry:timestamp_to_nano/1`; converting native units alone yields
the wrong epoch. The event field name `system_time_native` does not change this
requirement. Proposed pure boundary: `TraceRecord.convert(span, time_offset)`
returns a generated-message input or a specific tagged validation error. Encoding
accepts converted spans, their scope identities, and the authoritative resource.
These are future interfaces, not callable package APIs today.

## Configuration and bounds

Add `Config.transport/3` (pure, explicit environment map) and
`Config.load_transport/2` (runtime environment read) in Phase 5, returning
`{:ok, %Config{signal: :traces, resource: nil}}` or the existing specific tagged
configuration errors. Adapter options for pool ownership are validated separately.
Use explicit-option > signal environment > generic environment precedence. Existing
`Config.new/3` logs/metrics validation and error precedence stay intact. The trace
resolver rejects `:resource`, `:service_name`, `:service_version`,
`:service_instance_id`, `:max_queue`, `:flush_ms`, and `:shutdown_ms` as
`{:error, :unknown_option, key}`; SDK ownership settings do not belong here. It reads
endpoint, headers, compression, protocol, retries, and request limits; generic
endpoints append `/v1/traces`, signal endpoints remain exact. Only HTTP/protobuf is
supported. Custom CA/mTLS and canonical-exporter configuration parity remain out
of scope. Runtime environment is read at initialization; changes require restart.

| Limit | Contract |
| --- | --- |
| Spans per request | 512 maximum by default; distinct from SDK queue size |
| Span bytes | 65,536 generated protobuf bytes for one Span, excluding enclosing resource/scope |
| Request bytes | 1,048,576 full encoded request bytes before gzip, including all envelopes/schema URLs |
| Response bytes | 65,536 maximum |
| Callback deadline | 10,000 ms by default, starting before conversion |
| SDK export timeout | At least callback deadline + 2,000 ms; default integration value 12,000 ms |
| Retries | At most three retries (four attempts) per request, within the same callback deadline |

Bound traversal/materialization before exact generated-size verification; do not
materialize an arbitrarily large value merely to measure it. Reject an indivisible
span or envelope that cannot fit. Greedily form bounded requests, never split a
span, and stop after terminal request failure. Count unsubmitted spans as unsent.
An accepted earlier chunk is never replayed when a later chunk fails.

One monotonic deadline includes conversion, encoding, compression, HTTP, and retry
waits. The current `Transport.export/4` starts a fresh deadline on every call, so
Phase 5 needs a deadline-aware transport entry point rather than repeated calls
that reset the budget. An outer linked worker deadline also bounds conversion that
does not cooperatively check the clock. The SDK timeout margin allows the adapter
to return/report its own timeout; it is not a real-time scheduling guarantee.

The SDK defaults are a 2,048-span queue setting and periodic checks. Its admission
path does not enforce a strict per-insert count: a burst may exceed that setting.
Shipper limits bound materialized requests, not total SDK-retained memory. The
consumer must size and monitor the SDK independently; this exporter does not repair
SDK queue admission.

## Callback outcomes and diagnostics

| Outcome | SDK return | Accounting |
| --- | --- | --- |
| Valid initialization | `{:ok, state}` | No span outcome yet |
| Invalid configuration/resource setup | `:ignore` | Bounded configuration diagnostic |
| All submitted spans accepted | `:ok` | No drops |
| Warning-only partial response | `:ok` | Partial request diagnostic, zero drops |
| Rejected or invalid spans | `:failed_not_retryable` | Count only affected spans |
| Permanent transport/encoding failure | `:failed_not_retryable` | Failed chunk and unsent spans, once |
| Transient exhaustion/deadline before any confirmed accepted chunk | `:failed_retryable` | Count failed/unsent spans; SDK does not promise requeue |
| Failure after a confirmed accepted chunk | `:failed_not_retryable` | Preserve accepted count; never replay prior chunks |
| Exporter shutdown callback | `:ok` | No independent pool ownership |

Keep internal tagged errors specific; map them only at the SDK callback boundary.
For mixed local validation drops and successful chunks, return permanent failure.
Partial acceptance is never retried. Reject a response reporting more rejected
spans than submitted as invalid, instead of silently clamping it.

Emit existing export stop/exception events once per logical encoded request/chunk
after its retries, with `signal: :traces`; do not emit an outcome for every HTTP
attempt.
Transport owns submitted-request drop counts; the adapter reports only local
validation drops and never-submitted spans. Do not emit a second callback-wide
drop count for those same spans. Never include span payloads, endpoint credentials,
response bodies, or arbitrary exception terms in diagnostics. Hard SDK/VM death
can prevent final accounting; exact final diagnostics after forced termination
are not guaranteed. Lost responses can cause duplicate remote delivery.

## Feedback prevention

The owner approved a consumer-configured delegating sampler wrapper on September 17,
2026. It drops spans only while the exporter marker is set and otherwise delegates
to the configured sampler. The planned public module is
`OtlpShipper.TraceSampler`, configured by the consumer as a wrapper around its
existing sampler specification; it is not shipped in this phase. The package must not install it or mutate SDK configuration
on the consumer’s behalf. The marker belongs inside the actual HTTP worker, with
context restored in an `after` block. TCP-07 verifies this prototype against real loopback HTTP, Finch 0.20.0, and
`opentelemetry_finch` 0.2.0; production implementation remains Phase 6. SDK/API 1.7.0/1.5.0 has no generic suppression API, and released
`opentelemetry_finch` 0.2.0 has no documented exclusion/filter option. A random
context key or an unsampled parent is insufficient with an always-on sampler.
The marked request produces no exported span, while ordinary requests before and
after it are sampled by an always-on delegate. An always-off delegate stays off.
This supports the tested synchronous Finch path only: arbitrary instrumentation
that moves work to another process must propagate the marker and be verified
separately. Phase 6 must apply the marker inside the actual transport task; context
attached only in its parent does not automatically propagate to Elixir tasks.

## Evidence and remaining verification

Executable scenarios: `docs/features/trace-compatibility.feature` (TCP-01–09).
Assertions: `test/otlp_shipper/trace_compatibility_test.exs` and matching CucumberEx
steps. Machinery is in `test/support`, excluded from the Hex package and production
compilation. No production trace module or runtime dependency has been added.

Local environment: Elixir 1.19.5 / OTP 29. CI's pinned OTP 28 and minimum toolchain
must be checked separately. The initial stub failed all six ExUnit assertions and
all six Cucumber scenarios, establishing assertion-based red. Final observed results
and review status belong in the Phase 4 work record.

Source anchors in the installed SDK/API pair: `otel_batch_processor.erl`
(force_flush 141–143, timeout 257–263, terminate 314–322, insertion 352–365,
kill_runner 376–384, send_spans/export 427–444), `otel_tracer_server_sup.erl`
(27–61), `otel_span.hrl`, `opentelemetry.hrl`, `otel_resource.erl`,
`otel_attributes.erl`, `otel_events.erl`, `otel_links.erl`, and
`opentelemetry.erl` (`timestamp_to_nano/1`). These anchors describe inspected
versions, not a promise about future upstream versions.
