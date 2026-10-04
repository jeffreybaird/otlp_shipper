# Advanced export APIs

Most applications only need [logs](logs.md), [metrics](metrics.md), or the
[SDK migration guide](migration.md). Use these lower-level APIs when you already
have OTLP records or explicitly manage a named trace provider.

## Shared core

- `OtlpShipper.Config`: validated options and OTEL environment precedence.
- `OtlpShipper.Resource` / `Value`: service identity and typed OTLP attributes.
- `OtlpShipper.Encoder`: generated protobuf envelopes for logs and metrics.
- `OtlpShipper.Transport`: Finch POST, gzip, bounded retries, partial-response handling.
- `OtlpShipper.Buffer`: fixed-capacity ingress and one supervised batch worker.

The core accepts OTLP message maps. `OtlpShipper.LogHandler` converts Logger events;
`OtlpShipper.MetricsReporter` aggregates metric definitions. Both signals use the core independently.
Version 0.2.0 adds `OtlpShipper.TraceExporter`, using the existing tracing API, SDK,
and instrumentation.
The SDK owns the span queue; shipper converts and exports its batches within bounded
requests and deadlines.

## Send prepared log records

Start a dedicated Finch pool and buffer under your application's supervisor. This
example sends prepared OTLP log records; it does not install a Logger handler.

```elixir
{:ok, config} = OtlpShipper.Config.load(:logs,
  service_name: "checkout",
  endpoint: "http://localhost:4318/v1/logs"
)

export = fn records ->
  with {:ok, body} <- OtlpShipper.Encoder.encode(:logs, records, config.resource) do
    OtlpShipper.Transport.export(config, Checkout.OtlpFinch, body, length(records))
  end
end

children = [
  {Finch, name: Checkout.OtlpFinch, pools: %{default: [size: 1, count: 1]}},
  {OtlpShipper.Buffer, name: Checkout.OtlpBuffer, config: config, export: export}
]

# Add children to your application's supervision tree, in this order.
# Once started, obtain a handle for this buffer incarnation:
handle = OtlpShipper.Buffer.handle(Checkout.OtlpBuffer)
OtlpShipper.Buffer.enqueue(handle, %{body: OtlpShipper.Value.encode("ready")})
OtlpShipper.Buffer.flush(handle)
```

`enqueue/2` success means queued, not delivered. Acquire a new handle if the buffer
restarts. `flush/1` requests work asynchronously. Retention is in memory only.
Do not invoke `Transport.export/4` from a Logger or telemetry event callback.

## Trace protocol core

Version 0.2.0 provides low-level OTLP trace conversion, encoding, and bounded HTTP
export. The SDK integration builds on these core APIs. Keep the canonical SDK/API
and instrumentation. The SDK adapter and consumer-configured sampling wrapper are
described below.

`OtlpShipper.Config.transport/3` resolves trace transport settings without creating a
resource. It rejects service/resource identity, queue, flush, and shutdown options;
the supplied resource remains authoritative. `OtlpShipper.Config.new/3` continues to serve only
logs and metrics. Trace endpoints, headers, compression, protocol, and timeout use
explicit options, then trace-specific OTEL variables, then generic OTEL variables.

`OtlpShipper.TraceRecord.convert/3` validates normalized span maps without importing
SDK records. It preserves IDs, timestamps, flags, typed attributes, events, links,
and dropped counts. `OtlpShipper.Encoder.encode/3` accepts `:traces` and preserves
resource and instrumentation-scope identities. Neither operation stringifies invalid
attribute values or truncates resource/scope identity to make a request fit.

`OtlpShipper.TraceBatch.export/6` consumes a finite enumerable plus its exact declared
count, supplied by its caller. One deadline covers enumeration, conversion, encoding,
HTTP, retries, and synchronous diagnostic handlers. Defaults are 512 spans per
request, 65,536 protobuf bytes per span, 1,048,576 uncompressed bytes per complete
request, 65,536 response bytes, 10 seconds total, and three retries per request.
These request limits do not bound an SDK's retained queue.

Returned counters distinguish confirmed acceptance, rejection, invalid input,
submitted-but-unconfirmed failures, and unsent spans. An accepted chunk is never
replayed after another fails. A count mismatch may be discovered after earlier
chunks have been delivered; it cannot roll them back. A timeout does not prove
remote non-delivery. Diagnostic handlers execute within the deadline; forced
cancellation can omit their final events, while returned counters retain committed
outcomes and never recount accepted chunks as unsent.

## Named SDK trace provider

The adapter targets **SDK 1.7.0 / API 1.5.0**. Keep those packages and
existing instrumentation in the consumer. The package declares the SDK optional with `runtime: false`, preserving compile
ordering while leaving startup to the consumer. Logs/metrics consumers do not
acquire it. `OtlpShipper.TraceExporter` and
`OtlpShipper.TraceSampler` are compiled only when their SDK behaviours are available.
Adding the SDK to an existing consumer requires recompiling `otlp_shipper`.
Initialization rejects unverified SDK/API versions instead of assuming record
compatibility.

The consumer owns its supervisor, Finch pool, SDK provider, and batch processor.
Disable the SDK's default exporter in consumer configuration if using only the
explicit provider below:

```elixir
config :opentelemetry, traces_exporter: :none
```

Start the pool before its provider and use `:rest_for_one` so a pool crash restarts
the dependent SDK processes. Each independent instance needs distinct names:

```elixir
resource = :otel_resource.create(%{"service.name" => "checkout"})

batch = %{
  name: CheckoutTraces,
  resource: resource,
  exporter: {OtlpShipper.TraceExporter, [pool: CheckoutTraceFinch]},
  scheduled_delay_ms: 5_000,
  exporting_timeout_ms: 12_000
}

provider = %{
  id_generator: :otel_id_generator,
  sampler: {OtlpShipper.TraceSampler, {:parent_based, %{root: :always_on}}},
  processors: [{:otel_batch_processor, batch}],
  deny_list: []
}

children = [
  OtlpShipper.TraceExporter.pool_child_spec(CheckoutTraceFinch),
  %{
    id: CheckoutTraces,
    type: :supervisor,
    start: {:otel_tracer_server_sup, :start_link, [CheckoutTraces, resource, provider]}
  }
]

Supervisor.start_link(children, strategy: :rest_for_one)
```

The example uses an explicitly named provider. Configure your instrumentation to
use that provider; starting it does not redirect the SDK's global tracer. Direct
consumers can obtain its tracer with
`:otel_tracer_provider.get_tracer(CheckoutTraces, "checkout", "1.0", :undefined)`.
For existing instrumentation using the global tracer, use the tested consumer-owned
startup sequence in the [migration guide](migration.md), including its explicit
string `service.instance.id` override. SDK 1.7.0's generated integer instance ID
can exceed OTLP's signed 64-bit range; such a resource is rejected.

Exporter options are `:pool` plus the [trace transport options](configuration.md#trace-configuration). The named pool
must already exist. `init/1` reads the runtime environment once and returns `:ignore`
on invalid configuration; configuration changes require restart. Invalid-init
diagnostics run for at most 100 ms; a blocked subscriber may miss that diagnostic. The resource
passed by the SDK is authoritative. Export never starts a second span queue or
keeps the SDK table after returning. `shutdown/1` does not stop the consumer's pool.

Keep the SDK's `exporting_timeout_ms` at least **2,000 ms greater** than the exporter
`:timeout` (12,000 and 10,000 ms by default). The exporter cannot inspect or enforce
a processor's timeout from its callback options. Pool teardown and SDK shutdown
are best effort; the SDK can end remaining spans without invoking exporter shutdown.
`:otel_tracer_provider.force_flush/1` initiates a flush asynchronously. Observe
collector delivery or export diagnostics to establish completion.

Wrap your existing sampler specification with `OtlpShipper.TraceSampler` explicitly.
It drops spans created inside shipper HTTP workers and delegates all other sampling
decisions. The package never installs this wrapper or changes SDK configuration.
The tested feedback boundary is synchronous Finch instrumentation
`opentelemetry_finch` 0.2.0. Instrumentation that moves work to another process needs
separate marker propagation and verification. Without the wrapper, HTTP
instrumentation can turn export requests into more spans.

Callback results follow the SDK contract: complete acceptance and warning-only
responses return `:ok`; invalid/rejected spans and permanent errors return
`:failed_not_retryable`. Transient exhaustion or timeout before confirmed acceptance
returns `:failed_retryable`; after acceptance it returns `:failed_not_retryable` to
avoid replaying delivered chunks. SDK 1.7.0 does not requeue solely because of that
return value. Transport retries stay inside the exporter budget. Request diagnostics
are emitted once after retries, with local invalid and unsent spans counted separately.
Hard cancellation can prevent final diagnostics.

The adapter preserves fields exposed by the verified SDK. Its scope records have
no scope attributes/dropped count, and link records have no flags/remote-context
state. Those unavailable fields are not invented. Native timestamps use an explicit
epoch offset. SDK event/link collections are restored to their original order.
One SDK record must be read from ETS before validation; shipper bounds subsequent
normalization and encoded requests, not the SDK's retained batch or that source
record. The SDK's queue-size setting is periodically enforced and can be exceeded
by a burst. There is no durable or exactly-once delivery guarantee.
