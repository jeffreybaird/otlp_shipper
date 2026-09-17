Feature: Characterize the SDK boundary before implementing trace export
  Synthetic test-only exporters observe real SDK behavior.
  These probes do not implement the planned production trace exporter.

  @TCP-01 @TRC-02 @TRC-06 @phase4
  Scenario: TCP-01 Completed batch export releases the borrowed table
    Given the trace compatibility probe "batch_lifetime"
    When I run the real SDK compatibility probe
    Then the export worker owns the single-span table until completion

  @TCP-02 @TRC-06 @TRC-08 @phase4
  Scenario: TCP-02 SDK timeout terminates export work and its linked child
    Given the trace compatibility probe "cancellation"
    When I run the real SDK compatibility probe
    Then the timed-out worker and linked child are killed and the table is deleted

  @TCP-03 @TRC-02 @TRC-07 @phase4
  Scenario: TCP-03 A retryable callback result does not requeue the original batch
    Given the trace compatibility probe "retry_result"
    When I run the real SDK compatibility probe
    Then the original batch is exported once without replay after another flush

  @TCP-04 @TRC-09 @phase4
  Scenario: TCP-04 Flush initiation and shutdown callbacks have distinct semantics
    Given the trace compatibility probe "flush_shutdown"
    When I run the real SDK compatibility probe
    Then flush returns while export is blocked and termination does not invoke exporter shutdown

  @TCP-05 @TRC-06 @phase4
  Scenario: TCP-05 Periodic admission checks permit a burst beyond the queue setting
    Given the trace compatibility probe "queue_bound"
    When I run the real SDK compatibility probe
    Then the burst exceeds the configured queue setting before admission closes

  @TCP-06 @TRC-08 @TRC-09 @phase4
  Scenario: TCP-06 Consumer-owned transport lifetime survives missing shutdown callbacks
    Given the trace compatibility probe "owned_lifecycle"
    When I run the real SDK compatibility probe
    Then independent pools stop with their owners and conversion work respects the deadline

  @TCP-07 @TRC-07 @phase4
  Scenario Outline: TCP-07 Consumer-configured sampling prevents HTTP export feedback
    Given a real Finch instrumentation probe delegating to "<sampler>"
    When the worker sends ordinary, exporter-marked, and subsequent ordinary HTTP requests
    Then the loopback server accepts all three requests
    And the worker restores its original export marker after the marked request
    And the exported HTTP paths match the "<sampler>" sampling policy

    Examples:
      | sampler    |
      | always_on  |
      | always_off |

  @TCP-08 @TRC-09 @phase4
  Scenario: TCP-08 Pool failure restarts its dependent SDK without disrupting another instance
    When I probe an owned transport pool crash with two real SDK instances
    Then the dependent SDK processes restart and both instances export afterward

  @TCP-09 @TRC-03 @TRC-05 @phase4
  Scenario: TCP-09 Actual SDK records expose conversion inputs and dropped counts
    When I capture a real SDK span with remote context and overflowing metadata
    Then the SDK record preserves its configured identity resource and scope
    And its timestamps retain ordering after conversion to Unix nanoseconds
    And SDK accessors report the configured retained counts and each overflow loss
