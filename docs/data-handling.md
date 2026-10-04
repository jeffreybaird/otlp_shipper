# Data handling and observability

The package exports logs, metrics, and traces to consumer-configured OTLP/HTTP
endpoints. Telemetry can include log bodies, metric tags, span attributes/events,
resource identity, and trace/span IDs. The [README](../README.md) documents endpoint
and header precedence, limits, and failure behavior; the [migration guide](migration.md)
describes SDK resource and startup ownership.

Credentials come from runtime options or OTEL environment variables. Endpoint
userinfo and redirects are rejected. HTTPS uses Finch/Mint verification defaults;
plain HTTP is supported, including the default localhost Collector endpoints.
Custom certificate/mTLS environment settings are not implemented. Shipper's log
and metric queues are bounded and in memory, with no durable disk spool. Trace
buffering belongs to the SDK, whose queue cap can be exceeded by bursts.
Crashes, overload, and
exhausted retries can lose data; retrying can duplicate accepted data. Size limits
and truncation are not secret redaction: consumers must filter sensitive telemetry
before emission.

The host application owns deployment configuration, destination retention/access
controls, and consent requirements. This library operates no collection service.
These are implementation constraints and documented behavior, not a standalone
privacy policy.

- Keep credentials in consumer-supplied runtime configuration; never embed them in
  source, docs, fixtures, package archives, or logs.
- Use synthetic telemetry fixtures. Treat arbitrary attributes, resource data,
  endpoint query strings, and response bodies as potentially sensitive.
- Validate destinations and avoid forwarding credentials across redirect origins.
  Document any intentionally supported insecure local development connection.
- Bound diagnostic detail, payload sizes, retained data, and memory. Do not persist
  payloads to disk unless the package's agreed delivery contract requires it.
- Let the host configure logging and instrumentation. Avoid logging complete payloads
  or authentication headers. Use stable messages and structured metadata.
- Prevent the exporter's own failures and requests
  from recursively generating more exports. Test the relevant feedback path.

Review disclosure text whenever behavior changes. Browser permission forms, payment
consent fields, and a SaaS tenant model from the source projects do not apply here.
