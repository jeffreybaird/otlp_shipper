# Data handling and observability

The scaffold has no implemented shipping transport. This guide defines constraints
for future behavior; it is not a published privacy policy or a claim about delivery.

If network export is implemented, document the exact destination configuration,
data categories, authentication, TLS behavior, redirects, storage/retention, and
failure handling. The host application owns its deployment configuration and user
consent requirements. Do not invent a developer-operated collection service.

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
- If shipping logs or telemetry, prevent the exporter's own failures and requests
  from recursively generating more exports. Test the relevant feedback path.

Review disclosure text whenever behavior changes. Browser permission forms, payment
consent fields, and a SaaS tenant model from the source projects do not apply here.
