Feature: Use the existing tracing SDK with the shipper exporter
  Consumers retain their API, SDK, samplers, and instrumentation.
  They own the transport pool and explicitly select the exporter and sampler wrapper.

  @TSDK-01 @TRC-02 @TRC-09 @phase6
  Scenario: TSDK-01 Exporter shutdown leaves the consumer-owned pool running
    When I initialize and shut down the SDK exporter with a consumer-owned pool
    Then initialization succeeds and shutdown leaves that pool alive

  @TSDK-02 @TRC-03 @TRC-05 @phase6
  Scenario: TSDK-02 A real SDK batch reaches the collector with original identity
    When a named SDK provider exports a completed span through shipper
    Then the collector receives the span under the SDK resource and instrumentation scope

  @TSDK-01 @TRC-07 @phase6
  Scenario: TSDK-01 Collector rejection maps to the SDK permanent-failure result
    When the collector rejects the span in a real SDK record batch
    Then the exporter reports the SDK permanent-failure callback result

  @TSDK-03 @TRC-06 @TRC-08 @phase6
  Scenario: TSDK-03 SDK cancellation deletes its table and terminates export work
    When the SDK cancels a shipper export waiting for the collector
    Then its export worker is killed and the borrowed table is deleted

  @TSDK-04 @TRC-09 @phase6
  Scenario: TSDK-04 Repeated flush initiation does not acknowledge or replay delivery
    When I flush a real provider again before the first HTTP response completes
    Then flush returns before delivery and the accepted span is not replayed

  @TSDK-05 @TRC-10 @phase6
  Scenario: TSDK-05 Active span logs match the exported trace and detached logs clear context
    When I log inside a shipped SDK span and after detaching its context
    Then the first log matches the shipped span and the later log has no inherited IDs

  @TSDK-07 @TRC-09 @phase6
  Scenario: TSDK-07 A blocked initialization diagnostic cannot hold the SDK indefinitely
    When an invalid exporter configuration invokes a blocking diagnostic subscriber
    Then initialization returns ignore and its diagnostic worker terminates within the bound

  @TSDK-06 @TRC-10 @phase6
  Scenario Outline: TSDK-06 The sampler wrapper retains the configured delegate outside export
    When I sample ordinary and exporter-marked work with the "<delegate>" delegate
    Then ordinary work keeps the delegate decision and exporter-marked work is dropped

    Examples:
      | delegate   |
      | always_on  |
      | always_off |
