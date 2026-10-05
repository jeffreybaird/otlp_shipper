# otlp_shipper

Send Elixir logs, metrics, and traces to an OpenTelemetry collector over HTTP.
Use the components you need:

| Signal | Integration | Tracing SDK required? |
| --- | --- | --- |
| Logs | Ordinary `Logger` calls | No |
| Metrics | `Telemetry.Metrics` definitions | No |
| Traces | Your existing OpenTelemetry SDK and instrumentation | Yes |

[Hex package](https://hex.pm/packages/otlp_shipper/0.2.3) ·
[API documentation](https://hexdocs.pm/otlp_shipper/0.2.3/) ·
[Source](https://github.com/jeffreybaird/otlp_shipper)

## Install

Requires Elixir 1.19+ and OTP 28+. Add to your `mix.exs` dependencies:

```elixir
{:otlp_shipper, "~> 0.2.3"}
```

Then run `mix deps.get`.

You also need a reachable collector or backend accepting **OTLP/HTTP protobuf**.
The examples use a collector listening on `localhost:4318`. This package sends
telemetry; it does not start a collector.

## Send a log

Add this child to the `children` list in your application's `start/2` callback:

```elixir
{OtlpShipper.LogHandler,
 service_name: "checkout",
 endpoint: "http://localhost:4318/v1/logs"}
```

Restart your app with `iex -S mix`, then emit a log:

```elixir
require Logger
Logger.info("checkout complete", order_id: "example-42")
```

After the next batch flush (one second by default), look in your collector for
`checkout complete` under service `checkout`, with attribute `order_id=example-42`.
The handler owns its HTTP pool and buffer. Keep using your normal Logger calls.

[Log levels, attributes, and trace correlation →](docs/logs.md)

## Send a metric

Add this child to the same application supervisor:

```elixir
{OtlpShipper.MetricsReporter,
 service_name: "checkout",
 endpoint: "http://localhost:4318/v1/metrics",
 metrics: [Telemetry.Metrics.counter("checkout.request.count")]}
```

Restart the app, then emit the event:

```elixir
:telemetry.execute([:checkout, :request], %{count: 1}, %{})
```

The next interval exports `checkout.request.count` as a delta counter of `1`.
The metric name selects event `[:checkout, :request]` and measurement `:count`.
Counters count accepted events; they do not sum the measurement value.

[Histograms, units, tags, and metric types →](docs/metrics.md)

## Send traces

Keep your OpenTelemetry API, SDK, and instrumentation. Replace the trace exporter
using the [trace setup and migration guide](docs/migration.md), which covers
pool startup, resource identity, sampling, and rollback.

The verified pair is **SDK 1.7.0 / API 1.5.0**. Other versions are rejected at
initialization. Trace batching stays with the SDK.

## Connect to your collector

Use `endpoint` for a complete signal URL, or `base_endpoint` to append the signal
path automatically. You can also omit explicit service/endpoint options and set
`OTEL_SERVICE_NAME` and `OTEL_EXPORTER_OTLP_ENDPOINT` in the environment.
Explicit options win. Restart the component after changing configuration.

[Authentication, resources, environment variables, and limits →](docs/configuration.md)

## Know the delivery guarantees

Logs and metrics use bounded, in-memory queues. Overload, crashes, and exhausted
retries can lose data; retries can duplicate data when a response is lost. Trace
queueing belongs to the SDK. Flush calls do not confirm remote delivery.

Filter sensitive data before emission: size limits do not redact secrets. Avoid
user IDs and other unbounded metric tags. This package supports HTTP/protobuf;
use another exporter for gRPC, HTTP/JSON, or durable delivery requirements.

## Find the next step

| I want to… | Read |
| --- | --- |
| Diagnose missing data | [Troubleshooting](docs/troubleshooting.md) |
| Upgrade or check supported versions | [Compatibility](docs/compatibility.md) |
| Export prepared records or use a named trace provider | [Advanced APIs](docs/advanced.md) |
| Review release changes | [Changelog](CHANGELOG.md) |
| Develop or run conformance checks | [Contributor guide](https://github.com/jeffreybaird/otlp_shipper/blob/main/docs/README.md) |
