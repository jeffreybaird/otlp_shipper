Feature: Build bounded trace protocol exports without a tracing SDK adapter
  The shared core preserves normalized span data and original resource identity.
  It sends bounded HTTP protobuf requests while reporting each span outcome.

  @TPC-01 @TRC-04 @phase5
  Scenario: TPC-01 Trace transport configuration does not require a shipper resource
    When I resolve a trace base endpoint with no service identity
    Then the transport uses the trace path and has no generated resource

  @TPC-02 @TRC-03 @phase5
  Scenario: TPC-02 Normalized span conversion is strict and preserves identity
    When I convert a normalized trace span with its explicit clock offset
    Then the converted span preserves its IDs and Unix nanosecond timestamps
    And an invalid trace ID returns a field-specific error

  @TPC-03 @TRC-05 @phase5
  Scenario: TPC-03 Generated trace envelopes preserve SDK resource and scope identity
    When I encode normalized spans from two original instrumentation scopes
    Then the decoded request retains both scope schemas and the authoritative resource

  @TPC-04 @TRC-07 @phase5
  Scenario: TPC-04 The trace core sends bounded requests through a real HTTP boundary
    When I export two normalized spans with one span allowed per request
    Then the collector receives two valid trace requests and both spans are accepted

  @TPC-05 @TRC-07 @phase5
  Scenario: TPC-05 A partial rejection is counted without retrying accepted spans
    When I export two spans to a collector rejecting one span
    Then the trace outcome contains one accepted and one rejected span in one request

  @TPC-06 @TRC-08 @phase5
  Scenario: TPC-06 An expired shared deadline starts no HTTP request
    When I submit an encoded trace request after its absolute deadline
    Then the transport reports a timeout without starting HTTP

  @TPC-07 @TRC-07 @phase5
  Scenario: TPC-07 A terminal request failure preserves an earlier accepted chunk
    When I export three spans and the second request fails permanently
    Then the outcome preserves one accepted span and counts one failed and one unsent span
