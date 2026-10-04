# Migrating trace export to otlp_shipper 0.2.x

SDK-compatible trace export is available since 0.2.0. The examples below target
0.2.2. Since 0.2.1, log and metric instrumentation scopes report the loaded package
version; original trace scopes remain unchanged. Upgrading from 0.2.1 to 0.2.2
requires no trace configuration changes. It adds a Mint 1.10.2 security minimum;
run `mix deps.update otlp_shipper mint` and review your consumer lockfile.

## What changes

Replace the `opentelemetry_exporter` OTLP/HTTP export role. Keep
`opentelemetry_api`, `opentelemetry`, existing instrumentation, propagation, and
sampling policy. Logger and `Telemetry.Metrics` use shipper's own adapters; these
are not drop-in implementations of the experimental logs/metrics SDK APIs.
Do not leave two handlers/exporters sending the same signal unintentionally.

The verified trace pair is **SDK 1.7.0 / API 1.5.0**. Both minimum and current
consumer checks use that pair; there is no claim that other SDK record layouts
work. Initialization rejects unverified versions. Representative instrumentation
is **opentelemetry_finch 0.2.0**, with Finch 0.20.0 and the current resolved version.
A fresh release without the optional API/SDK remains supported for logs/metrics.

## Dependencies and startup

The consumer owns the global SDK and its configuration. Make it an included
application so OTP loads it without starting it before the Finch pool:

```elixir
# Consumer mix.exs
defp deps do
  [
    {:otlp_shipper, "~> 0.2.2"},
    {:opentelemetry, "== 1.7.0", runtime: false},
    {:opentelemetry_api, "== 1.5.0"},
    {:opentelemetry_finch, "== 0.2.0"}
  ]
end

def application do
  [
    mod: {Checkout.Application, []},
    extra_applications: [:logger],
    included_applications: [:opentelemetry]
  ]
end
```

Both shipper's optional SDK dependency and the consumer's direct dependency have
`runtime: false`: the compile-order edge remains, while the consumer owns SDK
startup. `included_applications` loads the SDK into the release. Dependencies that
also declare the SDK as an ordinary runtime application conflict with this setup;
inspect the consumer dependency tree and resolve startup ownership explicitly.
Remove the direct canonical exporter dependency and verify no other dependency
reintroduces it. Adding SDK/API to an existing consumer requires recompiling
`otlp_shipper`, because guarded integration modules are selected at compilation.

Configure the SDK in the **consumer's** config/runtime configuration before its
supervisor starts. Preserve your sampler by wrapping its existing specification:

```elixir
config :opentelemetry,
  resource: %{service: %{name: "checkout", version: "1.0", instance: %{id: "checkout-1"}}},
  resource_detectors: [:otel_resource_app_env],
  sampler: {OtlpShipper.TraceSampler, {:parent_based, %{root: :always_on}}},
  traces_exporter: {OtlpShipper.TraceExporter, [pool: Checkout.TraceFinch]},
  bsp_scheduled_delay_ms: 5_000,
  bsp_exporting_timeout_ms: 12_000
```

The explicit detector list makes service identity predictable in this example.
If retaining other detectors, verify their precedence and the final SDK resource.
Set `service.instance.id` to an explicit string unique to the running instance.
SDK 1.7.0 otherwise generates a 128-bit integer, which exceeds OTLP's signed 64-bit
attribute range. Shipper rejects that invalid resource instead of silently
stringifying it, so omitting this override can prevent trace export. Use the same
identity for logs and metrics; shipper does not replace or merge the SDK resource
inside trace callbacks.

Start the pool before the included SDK under a dedicated `:rest_for_one` supervisor:

```elixir
trace_children = [
  OtlpShipper.TraceExporter.pool_child_spec(Checkout.TraceFinch),
  %{
    id: :included_opentelemetry,
    type: :supervisor,
    shutdown: :infinity,
    start: {:opentelemetry_app, :start, [:normal, []]}
  }
]

Supervisor.start_link(trace_children,
  strategy: :rest_for_one,
  name: Checkout.TraceSupervisor
)

# Once SDK startup has completed:
OpentelemetryFinch.setup()
```

In an application, wrap that child list in your own Supervisor module and add its
child specification to the root supervisor before span producers. Do not also let
OTP start the ordinary SDK application or separately start another global provider.
The SDK application callback initializes global application tracers, preserving
existing Finch instrumentation without private tracer-cache manipulation.

This startup callback is an SDK implementation interface verified for 1.7.0, not a
promise of compatibility with future SDK versions. Pool restart restarts the
dependent SDK, and reverse-order shutdown stops the SDK before Finch. The
`:infinity` supervisor shutdown follows OTP semantics and is not a bounded
whole-application shutdown guarantee. Export attempts still have bounded timeouts;
crashes and restart gaps can lose spans. A named provider is an alternative only
for instrumentation configured to use it; the README shows that separate setup.
A named provider alone does not redirect the global tracer.

Configure logs and metrics with matching resource options:

```elixir
identity = [
  service_name: "checkout", service_version: "1.0", service_instance_id: "checkout-1"
]
children = [
  {OtlpShipper.LogHandler, identity},
  {OtlpShipper.MetricsReporter,
   Keyword.put(identity, :metrics, [Telemetry.Metrics.counter("checkout.request.count")])}
]
```

Add those children to your application supervisor. The SDK owns trace batching;
shipper owns only log/metric buffers. Instrumentation continues using its existing
API and context. Logs inside an active span inherit its IDs; detached logs do not
reuse stale inherited IDs.

## Endpoints, limits, and feedback

Trace transport precedence is explicit exporter options, trace-specific
`OTEL_EXPORTER_OTLP_TRACES_*` variables, then generic `OTEL_EXPORTER_OTLP_*`
variables. `endpoint` is an exact signal URL; `base_endpoint` appends `/v1/traces`.
The default is `http://localhost:4318/v1/traces`. Logs and metrics resolve their
own signal variables. Empty environment values are treated as unset. Options are
read once at startup; restart to change configuration.

Only HTTP/protobuf is supported. Gzip and bounded retry are supported. gRPC,
HTTP/JSON, custom certificate/mTLS environment settings, durable queues, and every
canonical exporter configuration option are not implemented. Do not copy
configuration blindly. Put secrets in runtime configuration; avoid credentials in
endpoint URLs.

Default trace limits are 512 spans/request, 65,536 encoded bytes/span, 1,048,576
uncompressed bytes/request, 65,536 response bytes, 10,000 ms total export budget,
and three retries per request. Resource and scope identity are preserved; oversized
or invalid records are rejected instead of silently changing identity. These
limits do not bound the SDK's retained queue or the one source record copied from
ETS before validation. Its queue cap is periodically enforced and can be exceeded
by a burst.

Keep SDK `bsp_exporting_timeout_ms` at least 2,000 ms above the exporter `timeout`.
The adapter cannot inspect this consumer setting. Timeout covers conversion,
encoding, HTTP, retries, and synchronous diagnostics inside the export callback.
No second span queue is added and no borrowed table is retained after return.

The sampler wrapper drops spans created inside shipper HTTP workers and delegates
all ordinary sampling to your existing sampler. It is required when HTTP
instrumentation would otherwise trace exports. The verified boundary is synchronous
Finch instrumentation. Instrumentation moving work to another process requires
separate context propagation and proof. The library never installs the wrapper or
changes another application's environment on your behalf.

## Flush, failure, and shutdown

`:otel_tracer_provider.force_flush()` initiates asynchronous work; it does not
acknowledge remote delivery. Observe decoded collector output or export diagnostics
before treating a flush as complete. Stop producers first, request flush, allow
bounded time for observed delivery, then stop the SDK before its pool. The SDK may
terminate remaining work without calling exporter shutdown. Exporter shutdown does
not own the pool.

Delivery is best effort, in memory. A timeout does not prove non-delivery. Retries
can duplicate already accepted data. Accepted chunks are not replayed after a later
chunk fails. Partial rejection, invalid spans, and permanent errors are reported;
SDK 1.7.0 does not requeue just because a callback returns `:failed_retryable`.
Transport retries stay within the exporter budget. Hard cancellation may prevent
final diagnostic callbacks. These are not exactly-once or durable delivery claims.

The verified SDK exposes no scope attributes/dropped count or link flags/remote
context state. The adapter preserves available fields and does not invent missing
ones. Sampling, context propagation, and instrumentation semantics remain SDK-owned.

## Verification and rollback

Run the package's strict test/analysis gate, SDK-absent/present release smoke, and
`sh scripts/replacement_consumer_smoke.sh`. Repeat the latter with
`OTLP_SMOKE_DEPENDENCY_SET=minimum`. It unpacks a Hex build into a fresh production
consumer, performs an ordinary instrumented Finch request, and checks decoded logs,
metrics, traces, IDs, resource identity, feedback suppression, and dependency absence.
It uses a local collector fixture; `mix otlp_shipper.conformance` separately checks
all three signals against pinned real Collector 0.160.0. See the README for Docker
setup. No production endpoint or credential is needed.

The proof emits elapsed time, VM memory snapshots, and a runtime application
inventory. These are descriptive smoke-run measurements, not throughput,
allocation, retained-heap, or comparative size benchmarks. No performance or
footprint advantage over the canonical exporter is claimed.

To roll back, stop producers and drain as above, restore the previously verified
canonical exporter dependency and configuration from your lockfile/release, remove
the included-SDK child and its shipper-only pool, and restore ordinary SDK startup
(remove its `runtime: false` and `included_applications` override). Restore your
original sampler when shipper no longer performs instrumented HTTP exports; if
keeping shipper logs/metrics, retain an appropriate suppression strategy and verify
it. Rebuild and deploy as a new release, then verify actual collector payloads and
absence of duplicate exporters. Logs and metrics can remain on shipper independently.
