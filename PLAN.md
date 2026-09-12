# PLAN.md — an OTLP logs + metrics shipper for Elixir

A build plan for an agent working alone. Read it end to end before starting; the
packaging decision in §2 and the dependency decision in §4 shape everything after.

Original design notation (superseded by confirmed decisions below): **`otlp_shipper`**, module root **`OTLPShipper`**.
Pick a real name before Phase 0 (§10) — but do not camp on the `opentelemetry_*`
prefix, which is the Erlang OTel org's namespace on Hex.

## Confirmed decisions — September 12, 2026

- Name: `otlp_shipper`; preserve the scaffold module spelling `OtlpShipper`.
  References to `OTLPShipper` below mean `OtlpShipper`.
- Public Hex package; `Telemetry.Metrics` reporter confirmed.
- HTTP client: Finch directly. The package owns retry/drop policy.
- Development authorized. Keep atomic commits and push each one to the phase branch.
- Phase branches and PR merge boundaries below remain in effect.

These decisions supersede the placeholder and HTTP-client choices below.

---

## 1. What this is

Two ways to get telemetry out of an Elixir app and into any OTLP/HTTP collector,
without running the OpenTelemetry SDK's metrics or logs machinery:

- **`OTLPShipper.LogHandler`** — a `:logger` handler that batches log events and POSTs
  them as `ExportLogsServiceRequest`. Records logged inside an `opentelemetry` span
  carry that span's ids, so logs and traces correlate.
- **`OTLPShipper.MetricsReporter`** — a `Telemetry.Metrics` reporter (the same shape as
  `TelemetryMetricsPrometheus` / `TelemetryMetricsStatsd`) that aggregates metric
  definitions over an interval and POSTs them as `ExportMetricsServiceRequest`.

Traces are **out of scope**: `opentelemetry_exporter` already exports them well. This
package fills the two holes it leaves.

The immediate consumer is `elixir_as_inf` (a personal OTLP hub) and the apps that feed
it — Marquee and residency-schedule — but nothing in the package may assume that hub.
It targets the OTLP/HTTP spec, so it works against an OTel Collector, Grafana Alloy,
Honeycomb, or anything else that speaks the protocol.

---

## 2. One package or two? — **One.**

Build a single package exposing both components.

**Why one:**

- The genuinely hard, shared part is the same for both signals: the HTTP transport
  (endpoint resolution, bearer auth, gzip, timeouts, retry, drop-on-failure), the
  protobuf encoding of `AnyValue` / `KeyValue` / `Resource`, and configuration from the
  `OTEL_EXPORTER_OTLP_*` environment variables. Split into two packages, that code is
  either duplicated or needs a third package that must be released in lockstep with
  both — which is the common failure mode of core/satellite splits with one maintainer.
- Every transport fix (a proxy header, a retry bug, a TLS quirk) would otherwise be
  fixed and released twice.
- The conformance suite — fixtures posted at a real collector and diffed — is shared,
  and it is the most valuable test asset here.
- `telemetry_metrics` is a near-zero-cost dependency for a logs-only user: it depends
  only on `telemetry`, which every Phoenix app already has. Make it a **hard**
  dependency, not an optional one; optional deps that change module availability are a
  well-known source of confusing failures.
- There is precedent for a signal-spanning package in this exact space:
  `opentelemetry_exporter` itself exports all three signals from one package.

**The strongest case against, which you should weigh before committing:** the two
components have different life expectancies. The log handler is a *stopgap* — it should
be deleted the day `opentelemetry_experimental` ships a working
`otel_exporter_logs_otlp` (§3). The metrics reporter is long-lived, because there is no
credible OTLP metrics path for Elixir today and won't be soon. Coupling something
designed to die to something designed to live means that when the SDK catches up you
deprecate half a package rather than archiving a whole one.

That cost is real but small: a deprecation notice in a minor release and removal in the
next major is ordinary library maintenance. The duplicated-transport cost is paid every
week; the deprecation cost is paid once.

**Split it later if** the metrics aggregation subsystem grows large enough to churn on
its own release cadence, or if either component gets handed to a different maintainer.
Design for that: keep `OTLPShipper.LogHandler` and `OTLPShipper.MetricsReporter`
depending only on the §4 core and never on each other, so a split is a file move.

---

## 3. Why it exists

Verified against the current dependency tree, not from memory:

- `opentelemetry` 1.7.0 ships **no logs handler** — there is no `otel_log_handler` in
  its `src/`.
- `opentelemetry_experimental` is the package that would carry logs and metrics SDKs.
  Its released version (0.5.1) predates `opentelemetry_exporter` 1.10's logs entry
  point and raises `undef` on export; the unreleased 0.6.0 on main hands a map to an
  exporter that expects an ETS table and raises `badarg`. Neither path emits a request.
- `telemetry_metrics` 1.2.0 has reporters for Prometheus, StatsD and others, but **none
  for OTLP**.

So an Elixir app today can export traces over OTLP and nothing else. A working
~200-line `:logger` handler already exists as a copy-into-your-app recipe at
`elixir_as_inf/examples/otlp_log_handler.ex`; this package is that recipe hardened,
tested, and joined by the metrics half.

**Re-check the first two bullets at the start of Phase 1.** If a release of
`opentelemetry_experimental` has since shipped a working logs exporter, stop and report
back before building the log handler — the metrics reporter may still be worth it alone.

---

## 4. The dependency decision: do not depend on `opentelemetry_exporter`

The example handler reuses `:opentelemetry_exporter_logs_service_pb` because the hub
already had that dependency. A standalone package must not: `opentelemetry_exporter`
pulls in `grpcbox`, the full `opentelemetry` SDK, and `tls_certificate_check`. Dragging
a gRPC stack into an app that wants to POST protobuf over HTTP defeats the point.

**Target:** vendor the OTLP `.proto` files and generate encoders at compile time with
`gpb` (build-time dependency only, `runtime: false`). Encoding only — this package never
decodes.

**Fallback, if the gpb build integration proves fragile:** depend on
`opentelemetry_exporter` and reuse its generated modules. Take this only after a timeboxed
spike, and record the reason in the README.

Dependency budget:

| Dependency          | Why                                        | Kind              |
|---------------------|--------------------------------------------|-------------------|
| `gpb`               | generate protobuf encoders                 | build, `runtime: false` |
| `telemetry_metrics` | the metric definition structs              | required          |
| `telemetry`         | transitive; also the package's own events  | required          |
| `opentelemetry_api` | read the current span for log correlation  | **optional**      |
| HTTP client         | see below                                  | decide in Phase 0 |

`opentelemetry_api` must be optional and guarded: an app with no tracing still gets its
logs, just without trace ids.

**HTTP client:** `:httpc` (zero deps, needs `:inets`/`:ssl` started, poor connection
reuse, awkward charlist API) versus `Req` (pleasant, pooled via Finch, adds a real
dependency tree). Decide in Phase 0 and write the reasoning down. Recommendation:
`Req`, because a telemetry exporter posting every few seconds wants connection reuse,
and Finch gives it. If you choose `:httpc`, the package must start `:inets` and `:ssl`
itself rather than assuming the host app did.

---

## 5. The shared core

`OTLPShipper.Config`
: Resolve endpoint, headers, timeout, gzip and resource from explicit options over
  `OTEL_EXPORTER_OTLP_*` environment variables, per the OTLP spec's precedence rules
  (signal-specific `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` beats generic
  `OTEL_EXPORTER_OTLP_ENDPOINT`; note the spec's path-appending rule differs between the
  two). Pure, doctested.

`OTLPShipper.Resource`
: Build the `Resource` message from `service.name`, `service.version`,
  `service.instance.id` and arbitrary extra attributes, honouring
  `OTEL_RESOURCE_ATTRIBUTES`. `service.name` is required; refuse to start without it
  rather than shipping `unknown_service`.

`OTLPShipper.Value`
: `AnyValue` / `KeyValue` encoding for strings, atoms, booleans, integers, floats,
  lists, maps, and a last-resort `inspect/1`. Pure, doctested, shared verbatim by both
  signals.

`OTLPShipper.Transport`
: POST an encoded body with content type, bearer or arbitrary headers, optional gzip,
  a timeout, and retry with exponential backoff and jitter on `429`/`503` and transport
  errors — honouring `Retry-After` when present. Gives up after a bounded number of
  attempts and **drops the batch**. Never blocks a caller, never raises into one.

`OTLPShipper.Buffer`
: The batching behaviour both components share: accumulate, flush on `max_batch` items
  or `flush_ms`, flush on terminate. **Bounded** — see §6.

Every export outcome emits `:telemetry`: `[:otlp_shipper, :export, :stop]` with
`%{count:, duration:, byte_size:}` and `%{signal:, status:}`, plus
`[:otlp_shipper, :export, :exception]` and `[:otlp_shipper, :dropped]` with a count and
a reason (`:queue_full | :export_failed`). Without these, a silently broken exporter is
indistinguishable from a quiet app — which is the failure mode the existing recipe has.

---

## 6. Phase 1 — the logger handler

Start from `elixir_as_inf/examples/otlp_log_handler.ex`. It works and its output is a
recorded fixture (`test/fixtures/otlp/elixir_fallback_logs.bin`), so the encoding is
already validated against a real consumer. Extraction is mostly hardening. **These are
defects in the existing recipe and each needs a test:**

1. **Unbounded mailbox.** `log/2` does a `GenServer.cast` per event with no
   backpressure; a log storm grows the queue until the VM dies. Bound the buffer, drop
   the oldest on overflow, count the drops, and emit them. (This mirrors the hub's own
   "drop before you fall over" principle — an exporter must never be the thing that
   takes an app down.)
2. **Unsupervised.** `adding_handler/1` calls `GenServer.start` unlinked; if that
   process dies, logging silently stops forever with the handler still installed. Put it
   under a supervisor the host app starts, or have the handler re-establish it.
3. **Silent failure.** `:httpc.request` results are ignored — a 401 from a bad token
   looks exactly like success. Emit telemetry, and log the first failure (and only the
   first, at a rate limit) through a handler-filtered path so it cannot recurse.
4. **No gzip, no retry, no timeout.**
5. **Recursion risk.** The exporter's own log output must never re-enter the handler.
   Tag it with a `domain` the handler drops.
6. **Truncation.** A single enormous log body can blow the collector's request limit.
   Cap attribute and body length, and set `dropped_attributes_count` honestly.

Keep from the original: the severity mapping, the structured-report `kvlist` body, the
`otel_trace_id` metadata handling, and dropping the internal `:logger` metadata keys.

**Acceptance:** a `Logger.info` inside an `opentelemetry` span produces an
`ExportLogsServiceRequest` whose record carries the right severity number, body shape,
attributes and the span's 16-byte trace id and 8-byte span id; the same outside a span
carries empty ids; a 10,000-event burst drops rather than growing unboundedly and
reports how many it dropped; a collector returning 503 twice then 200 results in one
delivered batch.

---

## 7. Phase 2 — the metrics reporter

The larger and less charted half. `use GenServer`, `start_link(metrics: [...], ...)`,
attach to each metric's event, aggregate in ETS or state, export on an interval.

**Mapping from `Telemetry.Metrics` to OTLP:**

| `Telemetry.Metrics` | OTLP                                    | Notes                                       |
|---------------------|-----------------------------------------|---------------------------------------------|
| `counter/2`         | `Sum`, monotonic                        | count of events                             |
| `sum/2`             | `Sum`, monotonic unless negatives seen   | sums the measurement                        |
| `last_value/2`      | `Gauge`                                  |                                             |
| `distribution/2`    | `Histogram`, explicit bounds             | bounds from `reporter_options[:buckets]`    |
| `summary/2`         | **refuse at init**                       | no OTLP equivalent; `Summary` is legacy/deprecated |

Refusing `summary` loudly at `start_link` is better than silently dropping it at
runtime. Say so in the error, and name `distribution` as the fix.

**Decisions to make and document:**

- **Temporality: delta.** Reset accumulators each interval; `start_time_unix_nano` is
  the start of the interval, `time_unix_nano` the end. Delta is far simpler to get right
  than cumulative and is accepted by every major backend. Cumulative can come later
  behind an option; do not build both now.
- **Tags become attributes.** `tag_values/1` runs before aggregation, as it does in other
  reporters. Cardinality is the user's problem, but document the footgun and consider a
  configurable series cap that drops-and-counts rather than exploding.
- **Units.** `Telemetry.Metrics` unit conversion (`{:native, :millisecond}`) happens
  before aggregation; the OTLP `unit` field takes the converted unit as a UCUM string
  (`ms`, `s`, `By`, `1`).
- **An interval with no events emits nothing** for that series. Do not send zeros.

**Acceptance:** a fixture app emitting known `telemetry` events produces an
`ExportMetricsServiceRequest` with exact counts, sums, gauge values and histogram bucket
counts; two consecutive intervals show delta semantics (the second does not include the
first's events); a metric with `tags` produces one data point per tag combination with
the tags as attributes; `summary/2` is refused at `start_link` with a message naming the
alternative.

---

## 8. Phase 3 — conformance, docs, release

- **A fake collector for tests.** A Bandit/Plug server started in the test suite that
  accepts `POST /v1/{logs,metrics}`, decodes the body with gpb and hands the decoded
  message to the test. This is the backbone of every acceptance criterion above — build
  it first in Phase 0, not here.
- **Conformance against a real collector.** A `mix` task, excluded from CI by default,
  that boots an OTel Collector in Docker with a debug exporter and asserts both signals
  arrive and parse. The fake collector proves you encode what you think; only a real one
  proves the wire format is right.
- **Docs:** a README that opens with the 10-line setup for each component, an
  `OTEL_*` configuration table, the telemetry events, the cardinality and truncation
  warnings, and an honest "when not to use this" pointing at
  `opentelemetry_experimental` for the day it works.
- **Hex release:** `0.1.0`, MIT, ExDoc, CI on the Elixir/OTP pair in `.tool-versions`,
  `mix hex.audit` and `mix dialyzer` clean.

---

## 9. Order

```
0 core (config, resource, value, transport, buffer, fake collector)
     ├─▶ 1 log handler ────┐
     └─▶ 2 metrics reporter ┴─▶ 3 conformance + docs + release
```

Phase 1 before 2: it is smaller, it starts from working code, and it proves the whole
core (config → resource → encode → transport → retry → telemetry) against the fake
collector before the harder aggregation work lands on top.

**Sequencing constraint with the hub:** `elixir_as_inf` returns `501` for
`POST /v1/metrics` (its Phase 6, currently unstarted). The metrics reporter therefore
cannot be tested end-to-end against that hub until the hub implements the endpoint. This
is not a blocker — develop against the fake collector and a real OTel Collector, which
is the better target anyway — but do not plan a "point it at the hub and watch" demo for
Phase 2.

---

## 10. Decisions for the owner, before Phase 0

1. **Package name.** `otlp_shipper` is a placeholder. Avoid the `opentelemetry_*`
   prefix.
2. **HTTP client** — `Req` or `:httpc` (§4). Recommendation: `Req`.
3. **Public or private Hex?** Public changes the bar: a stable API, a CHANGELOG, and
   semver discipline. Private/internal means you can break things freely.
4. **Confirm the reading of "OTLP reporter"** — this plan assumes a
   `Telemetry.Metrics` reporter for metrics. If you meant something else (a trace
   exporter, a generic `telemetry` handler), stop here and say so; §7 is the wrong plan.

---

## 11. Conventions for the agent

The owner's house style, carried over from `elixir_as_inf` and expected here:

- Every public function has an `@doc` with at least one real doctest (exempt: functions
  that do I/O). Pure helpers — config resolution, value encoding, severity mapping,
  bucket layout — must carry doctests with real values, never placeholders.
- Every addition that adds behaviour comes with a test that validates that behaviour.
  Every `case`/`cond`/`if` arm gets a test.
- Fallible functions return tagged tuples: `{:error, :unauthorized}`,
  `{:error, :overloaded}`, `{:error, :transport, reason}`. Never a bare
  `{:error, changeset}`, never a string message from a public function.
- One function, one job. Private functions are named for what they do to the data
  (`reject_internal_metadata/1`, not `filter/1`).
- Atomic commits, conventional prefixes (`feat:`, `fix:`, `refactor:`, `test:`), linear
  history, no merge commits. A full check (`format --check-formatted`, `compile
  --warnings-as-errors`, `test`, `dialyzer`) passes before every commit.
- **Never modify an existing test to make it pass**, never weaken an assertion, never
  delete a test to resolve a failure. If a test looks wrong, flag it and ask.
- Never hand-write protobuf encoding. Generate it.
- No `IO.inspect` in committed code.

Work phase by phase. Each phase is a branch and a PR; do not start the next before the
previous is merged.
