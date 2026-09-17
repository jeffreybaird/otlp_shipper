# Planned tracing acceptance specification for PLAN.md sections 12-16.
# These scenarios are not registered with executable step definitions yet.
# Develop executable coverage phase by phase; do not add placeholder or pending steps.
# @probe scenarios verify evidence and decisions, not an implemented trace exporter.
# Numeric limits and callback mappings refer to the contract approved in Phase 4.
Feature: Export SDK traces through the shared OTLP HTTP layer
  Applications retain the OpenTelemetry API, SDK, and instrumentation.
  Shipper exports completed spans without changing existing logs or metrics.

  @TRC-01 @phase4 @probe
  Scenario: TRC-01-01 Prove optional SDK compilation before choosing adapter packaging
    Given the candidate SDK integration and a fresh logs and metrics consumer
    And the tracing API, SDK, and canonical exporter are absent
    When the compatibility probe compiles the package and builds a production release
    Then the release starts and exports a log and a metric
    And the decision record identifies the compilation and dependency isolation strategy

  @TRC-01 @phase5
  Scenario: TRC-01-02 Preserve existing logs and metrics contracts while adding trace core support
    Given the trace protocol and shared core changes
    When the existing logs and metrics regression suite runs
    Then resource validation, endpoint resolution, encoding, limits, and delivery behavior remain valid
    And no tracing component is required to start either signal

  @TRC-01 @phase7
  Scenario: TRC-01-03 Ship a usable release without tracing dependencies
    Given a fresh consumer of the candidate package archive
    And the tracing API, SDK, and canonical exporter are absent
    When its production release emits a log and a metric to a local collector
    Then both payloads contain the expected values
    And no tracing or gRPC dependency is required by those components
    And the release runs without gpb

  @TRC-02 @phase4 @probe
  Scenario: TRC-02-01 Establish the supported SDK and callback contract
    Given the installed SDK and API pair as a compatibility candidate
    When the probe examines current releases and executes candidate minimum and current pairs
    Then the decision record identifies tested SDK, API, and toolchain versions
    And it records callback shapes, record layouts, and fields unavailable from each SDK
    And it defines callback and diagnostic outcomes for success, invalid configuration, invalid data, encoding failure, partial acceptance, exhausted retries, and deadline expiry
    And unsupported version combinations are not advertised as compatible

  @TRC-02 @phase6
  Scenario: TRC-02-02 Export through each supported SDK batch processor
    Given each SDK and API pair in the approved compatibility matrix
    And the consumer configures the proposed trace exporter through the SDK interface
    When existing API instrumentation completes a sampled span
    Then the collector receives the span through the shipper exporter
    And initialization, export, and shutdown use the approved SDK callback shapes
    And the consumer retains ownership of its provider, sampler, and propagation

  @TRC-02 @phase6
  Scenario: TRC-02-03 Preserve SDK sampling decisions
    Given a supported SDK batch processor and sampler
    When instrumentation completes one sampled span and one unsampled non-recording span
    Then the collector receives the sampled span with its sampling flags preserved
    And shipper does not fabricate an exportable span for the unsampled operation

  @TRC-03 @phase4 @probe
  Scenario: TRC-03-01 Record a complete conversion mapping
    Given supported SDK records and the vendored trace schemas
    When the compatibility probe compares their span, event, link, resource, and scope fields
    Then the decision record maps supported fields to generated protocol fields
    And it records timestamp units, ID widths, dropped counts, and unavailable fields
    And it defines pure conversion and encoding interfaces without hand-written wire encoding

  @TRC-03 @phase5
  Scenario: TRC-03-02 Preserve complete span meaning on the wire
    Given a completed span with trace and span IDs, parent ID, tracestate, flags, name, and kind
    And start and end timestamps, status, attributes, events, and links
    And nonzero dropped attribute, event, and link counts supported by the SDK
    When the span is converted and posted to the fake collector
    Then the decoded request preserves every supported field and dropped count
    And IDs use the required byte widths and timestamps retain nanosecond meaning

  @TRC-03 @phase5
  Scenario: TRC-03-03 Preserve root spans and absent optional fields
    Given a valid root span with no parent, events, links, or optional status description
    When the span is encoded and decoded by the fake collector
    Then the request represents the original root span and absent optional fields
    And no parent ID, event, link, or description is fabricated

  @TRC-03 @phase5
  Scenario: TRC-03-04 Preserve supported boundary values and typed attributes
    Given valid ID and timestamp boundary values from the approved conversion contract
    And supported scalar and array attributes on spans, events, and links
    When those spans are converted and decoded
    Then the values retain their types and precision
    And distinct valid IDs and timestamps do not collapse to the same encoded value

  @TRC-04 @phase4 @probe
  Scenario: TRC-04-01 Separate trace transport configuration from resource creation
    Given the existing logs and metrics configuration interfaces
    When Phase 4 defines the trace configuration interface
    Then its contract separates transport resolution from SDK resource identity
    And it defines defaults, units, supported options, validation errors, and restart requirements
    And existing logs and metrics service identity validation remains required
    And trace resource options are not accepted and silently ignored

  @TRC-04 @phase5
  Scenario: TRC-04-02 Resolve trace settings with documented precedence
    Given conflicting explicit, trace-specific environment, and generic environment settings
    When trace transport configuration resolves each supported configurable setting
    Then explicit settings take precedence over trace-specific settings
    And trace-specific settings take precedence over generic settings
    And absent settings use the approved defaults
    And another signal's environment settings do not configure traces

  @TRC-04 @phase5
  Scenario: TRC-04-03 Append the trace path only for base endpoints
    Given a generic base endpoint with an existing path prefix
    When trace configuration resolves that endpoint
    Then the endpoint appends "/v1/traces" to that prefix
    When configuration instead supplies an exact trace endpoint
    Then the exact endpoint is retained without an appended trace path

  @TRC-04 @phase5
  Scenario: TRC-04-04 Reject unsupported configuration before exporting
    Given an unsupported protocol, invalid endpoint, invalid limit, or unsupported option
    When trace configuration is validated
    Then validation returns the corresponding approved specific error
    And no HTTP request is made
    And unsupported custom CA or mTLS options are not silently accepted

  @TRC-04 @phase5
  Scenario: TRC-04-05 Apply headers and compression at the HTTP boundary
    Given valid trace configuration with custom headers and gzip enabled
    When a trace request reaches the fake collector
    Then the request uses POST and the configured trace endpoint
    And it carries the configured headers and protobuf content type
    And its gzip body decodes to the expected trace request

  @TRC-04 @phase6
  Scenario: TRC-04-06 Read environment configuration once per initialization
    Given an initialized exporter using trace environment settings
    When the environment changes while the exporter is running
    Then subsequent exports retain the initialized configuration
    When the exporter is restarted through the documented lifecycle
    Then the new instance uses the updated environment settings

  @TRC-05 @phase5
  Scenario: TRC-05-01 Preserve SDK resource authority including default identity
    Given an SDK resource with its own service identity and attributes
    And conflicting shipper resource environment variables
    When spans using that resource are exported
    Then the decoded request contains the SDK resource without rebuilding its identity
    And the same rule applies when the SDK supplies its default service identity

  @TRC-05 @phase5
  Scenario: TRC-05-02 Keep resources and instrumentation scopes distinct
    Given spans from two providers with different resources
    And multiple instrumentation scopes with names, versions, attributes, and supported schema URLs
    When their trace requests are decoded
    Then each span remains associated with its original resource and scope
    And supported resource and scope schema URLs remain attached to the correct envelope
    And scopes are not relabeled as "otlp_shipper"

  @TRC-06 @phase4 @probe
  Scenario: TRC-06-01 Observe SDK batch and ETS ownership
    Given each candidate SDK batch processor and a synthetic probe exporter
    When a batch export completes and another export exceeds the SDK worker timeout
    Then the probe records callback execution, ETS ownership, deletion, and worker cancellation
    And the decision record explains how the adapter avoids retaining borrowed ETS data
    And it records measured burst retention and the SDK queue admission boundary
    And periodic queue checks are not described as a strict shipper memory bound

  @TRC-06 @phase6
  Scenario: TRC-06-02 Finish export work before returning the borrowed batch
    Given an SDK batch containing completed spans
    When the adapter's export callback returns
    Then the callback has completed its bounded conversion and transport work
    And shipper has not enqueued another trace batch
    And no shipper task retains or reads the SDK ETS table afterward

  @TRC-06 @phase6
  Scenario: TRC-06-03 Keep network work off concurrent span producers
    Given the supported SDK batch configuration and a slow collector
    When concurrent application processes complete spans
    Then trace HTTP work runs in the export path rather than producer callbacks
    And producer completion does not wait for the collector response
    And shipper creates no additional pending-span queue

  @TRC-07 @phase5
  Scenario: TRC-07-01 Report full acceptance and empty partial-success responses
    Given a trace request containing a known number of spans
    When the collector returns full success or an empty partial-success message
    Then the request is classified as fully accepted
    And export diagnostics count spans rather than requests or bytes
    And no rejected spans are reported

  @TRC-07 @phase5
  Scenario: TRC-07-02 Report partial rejection without replaying accepted spans
    Given a trace request containing a known number of spans
    When the collector reports a valid nonzero rejected-spans count
    Then diagnostics report the partial outcome and rejected count exactly once
    And the partially accepted request is not retried
    And accepted spans are not counted as dropped

  @TRC-07 @phase5
  Scenario: TRC-07-03 Preserve warning-only partial response meaning
    Given a successful HTTP response with a partial-success warning and zero rejected spans
    When the response is classified
    Then diagnostics preserve the warning-only partial outcome
    And no span rejection count is invented
    And the request is not retried

  @TRC-07 @phase5
  Scenario: TRC-07-04 Reject untrustworthy collector responses within bounds
    Given a collector response that is malformed, exceeds the configured response byte limit, or has an invalid rejected-spans count
    When the transport processes the response
    Then it reports the approved failure classification without claiming full acceptance
    And response processing respects the configured byte bound
    And drop accounting follows the approved outcome matrix without double counting

  @TRC-07 @phase5
  Scenario: TRC-07-05 Drop invalid and individually oversized spans honestly
    Given a batch containing valid spans, an invalid span, and an individually oversized span
    When requests are constructed under the configured span and request limits
    Then valid spans are exported within those limits
    And each invalid or oversized span is dropped and counted once
    And no IDs are fabricated, no span is split, and no span meaning is altered to make it fit

  @TRC-07 @phase5
  Scenario: TRC-07-06 Honor exact request limits including the protocol envelope
    Given spans whose encoded requests reach the configured span-count and byte limits
    And additional spans that would exceed those limits
    When the batch is split into requests
    Then each request respects the span-count and uncompressed encoded-byte limits including its envelope
    And every admitted span appears in exactly one constructed request
    And gzip does not allow an oversized uncompressed request through

  @TRC-07 @phase6
  Scenario: TRC-07-07 Map callback outcomes and diagnostics without leaking telemetry data
    Given each outcome in the approved callback matrix
    When the real SDK invokes the exporter for that outcome
    Then the callback returns its approved SDK result
    And diagnostics use "traces" as the signal and the approved request and callback accounting
    And diagnostics remain bounded and omit credentials and span payloads

  @TRC-07 @phase6
  Scenario: TRC-07-08 Suppress exporter instrumentation feedback
    Given supported HTTP instrumentation and active logs and metrics exporters
    When trace HTTP exports succeed and fail
    Then exporter HTTP work does not create an endless stream of exportable spans
    And exporter diagnostics do not recursively create exported logs or metrics
    And unrelated application instrumentation continues to record normally

  @TRC-07 @phase4 @probe
  Scenario: TRC-07-09 Prove the instrumentation suppression mechanism before adapter implementation
    Given a synthetic SDK consumer with a candidate HTTP instrumentation library
    And the existing Logger and metrics exporter recursion guards
    When the probe sends synthetic exporter HTTP requests using the SDK suppression mechanism
    And it records an unrelated instrumented application operation
    Then exporter HTTP requests do not produce exportable spans
    And the unrelated application operation still records its expected spans
    And the existing Logger and metrics recursion guards remain effective
    And the decision record identifies the tested SDK, API, instrumentation versions, and suppression mechanism
    And the evidence does not require or introduce a production trace adapter

  @TRC-08 @phase4 @probe
  Scenario: TRC-08-01 Establish limits and cancellation before publishing defaults
    Given a synthetic batch with costly conversion, multiple chunks, and delayed HTTP responses
    When the probe exercises candidate limits and SDK worker timeouts
    Then the decision record defines numeric defaults, units, span-size measurement, and envelope accounting
    And it demonstrates one deadline covering conversion, all requests, and retry waits
    And it specifies the SDK timeout margin and observed cancellation behavior
    And it defines unsent-span and partial-chunk accounting

  @TRC-08 @phase5
  Scenario: TRC-08-02 Retry transient failures within the remaining budget
    Given a collector that returns retryable HTTP or transport failures followed by success
    And its Retry-After delay fits within the remaining callback budget
    When the trace request is exported
    Then attempts follow the shared retry policy and honor Retry-After
    And attempt count and elapsed work stay within the configured retry and deadline limits
    And diagnostics report the final outcome without counting retried spans as new spans

  @TRC-08 @phase5
  Scenario: TRC-08-03 Stop when retry delay or retry count exhausts the budget
    Given persistent retryable failures or a Retry-After delay beyond the remaining deadline
    When the retry limit or callback deadline is reached
    Then no further request is attempted
    And the unsent or failed spans receive the approved terminal accounting
    And a retryable callback result is not treated as a promise that the SDK will requeue spans

  @TRC-08 @phase5
  Scenario: TRC-08-04 Do not retry permanent failures
    Given a collector returning a permanent HTTP failure
    When a trace request is exported
    Then the failed request is not retried
    And the failure and affected span count follow the approved outcome matrix

  @TRC-08 @phase5
  Scenario: TRC-08-05 Share one deadline across conversion and multiple chunks
    Given an SDK batch requiring several bounded requests
    When conversion or an earlier request consumes the remaining callback budget
    Then later chunks do not receive a fresh deadline
    And conversion and requests stop according to the approved cancellation contract
    And spans not sent are accounted for separately from confirmed accepted spans

  @TRC-08 @phase5
  Scenario: TRC-08-06 Preserve successful chunks when a later chunk fails
    Given a batch split into multiple requests
    When an earlier chunk succeeds and a later chunk fails or is partially rejected
    Then the successful chunk is not replayed
    And accepted, rejected, failed, and unsent spans follow the approved accounting
    And no span is counted in two terminal outcomes

  @TRC-08 @phase6
  Scenario: TRC-08-07 Cancel local work when the SDK terminates the export worker
    Given conversion or retry work is active in a real SDK export callback
    When the SDK cancels its export worker
    Then no orphaned shipper conversion or retry task survives cancellation
    And no later retry uses the destroyed SDK table
    And a request already sent is not reported as certainly undelivered solely because cancellation occurred

  @TRC-08 @phase6
  Scenario: TRC-08-08 Disclose duplicate delivery after a lost response
    Given the collector accepts a request but its response is lost
    When the shared retry policy sends the request again within budget
    Then the collector may observe duplicate spans
    And the documented delivery contract promises neither durable nor exactly-once delivery

  @TRC-09 @phase4 @probe
  Scenario: TRC-09-01 Prove initialization order and resource ownership
    Given a synthetic SDK consumer with two independently configured exporter instances
    When the probe starts, restarts, and stops their supervised resources
    Then the decision record provides a tested consumer-owned startup sequence
    And it defines Finch ownership, naming, initialization failures, and restart behavior
    And it demonstrates cleanup even when the SDK omits exporter shutdown
    And it does not rely on another application's global Finch configuration

  @TRC-09 @phase4 @probe
  Scenario: TRC-09-02 Record actual flush and shutdown behavior
    Given a candidate SDK with queued spans and an in-flight export
    When the probe initiates force flush and then bounded shutdown
    Then the record distinguishes flush initiation from observed delivery completion
    And it records whether exporter shutdown is invoked and how remaining resources are released
    And it describes what can be lost at the shutdown deadline or on a crash

  @TRC-09 @phase6
  Scenario: TRC-09-03 Reject invalid initialization without leaking resources
    Given invalid trace configuration or an unavailable required supervised resource
    When exporter initialization is attempted
    Then it returns the approved initialization outcome with bounded diagnostics
    And no owned resource or HTTP request leaks from the failed attempt
    And the consumer's SDK and application environment are not mutated

  @TRC-09 @phase6
  Scenario: TRC-09-04 Isolate independently owned instances
    Given two exporter instances with distinct pools, endpoints, and credentials
    When both export and one instance is stopped
    Then each request uses only its own configuration and resource ownership
    And the other instance continues exporting
    And stopping one instance does not stop resources owned by the other

  @TRC-09 @phase6
  Scenario: TRC-09-05 Recover supervised resources after failure
    Given an initialized exporter under the approved supervision strategy
    When its owned transport process fails and supervision restarts it
    Then later exports use the recovered resource according to the approved restart contract
    And stale handles do not cause uncontrolled retries or resource leaks

  @TRC-09 @phase6
  Scenario: TRC-09-06 Observe repeated flush completion without promising synchronous delivery
    Given queued spans and an export already in progress
    When the consumer initiates repeated SDK force flushes
    Then flush return alone is not asserted as delivery success
    And completion is established through observed collector or export outcomes
    And shipper does not replay completed chunks or retain borrowed batches

  @TRC-09 @phase6
  Scenario: TRC-09-07 Bound shutdown even when the collector stalls
    Given queued spans and a collector that does not complete requests
    When the consumer stops the supervised tracing resources
    Then shutdown finishes within the approved shutdown bound
    And all owned resources are released even if exporter shutdown was not invoked
    And remaining data is treated according to the documented best-effort loss contract

  @TRC-10 @phase6
  Scenario: TRC-10-01 Correlate active spans and clear context afterward
    Given the Logger handler and a supported SDK trace exporter
    When an application logs inside an active sampled span and again after context detach
    Then the first exported log has the same trace ID and span ID as the exported span
    And the later log does not inherit the detached span's IDs

  @TRC-10 @phase6
  Scenario: TRC-10-02 Preserve nested and remote-parent relationships
    Given an incoming remote parent context and application instrumentation creating a child and nested span
    When the SDK exports the completed spans through shipper
    Then their trace IDs and parent IDs preserve the original relationships
    And supported remote-parent flags and tracestate retain their meaning
    And shipper does not replace SDK context propagation

  @TRC-10 @phase6
  Scenario: TRC-10-03 Preserve exception status and event context
    Given application instrumentation records an exception and status on a span
    And records events and links through the supported SDK API
    When that span is exported
    Then the decoded status, exception event attributes, event timestamps, and links match the SDK data
    And export does not change application exception handling

  @TRC-10 @phase7
  Scenario: TRC-10-04 Retain representative instrumentation without shipping its framework
    Given a separate consumer using an existing supported instrumentation library
    And the canonical exporter is absent
    When the instrumented operation runs with shipper as the trace exporter
    Then its expected spans and relationships reach the collector
    And the instrumentation fixture's framework dependencies do not enter shipper's runtime dependencies

  @TRC-11 @phase7
  Scenario: TRC-11-01 Export all signals from a fresh packaged application
    Given a production consumer built from the candidate package archive
    And a supported SDK and API pair but no canonical exporter
    When it emits a log, a metric, and an instrumented trace
    Then the local collector decodes the expected payload from each signal
    And the release runs without gpb or a hidden probe dependency
    And the proof is repeated for the supported minimum and current dependency pairs

  @TRC-11 @phase7
  Scenario: TRC-11-02 Prove real Collector trace and log interoperability
    Given the opt-in pinned real Collector conformance environment
    When the packaged consumer exports all three signals and logs inside a span
    Then Collector output preserves expected span fields and parent relationships
    And the log correlates with the exported span
    And metrics retain their expected values
    And HTTP success alone is not accepted as conformance evidence

  @TRC-11 @phase7
  Scenario: TRC-11-03 Provide migration and rollback without claiming universal parity
    Given passing replacement evidence and the supported configuration matrix
    When migration guidance is prepared
    Then it shows retained API, SDK, and instrumentation dependencies and exporter replacement
    And it documents consistent resources, endpoint precedence, startup, flush, shutdown, and retry duplicates
    And it identifies deferred protocols and configuration options and provides canonical-exporter rollback guidance
    And performance or dependency-size advantages are claimed only with recorded measurements

  @TRC-11 @phase7
  Scenario: TRC-11-04 Prepare a release only after all acceptance gates pass
    Given recorded evidence for every tracing acceptance ID
    When the candidate release passes package checks, audit, documentation, consumer smokes, and real Collector conformance
    Then README, CHANGELOG, and product decisions distinguish implemented tracing from deferred work
    And the candidate version is confirmed through release readiness
    And Hex publication and documentation upload wait for separate release authorization
