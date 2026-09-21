Feature: Validate trace interoperability and replacement evidence
  Recorded Collector output is checked structurally for payload relationships.
  Synthetic report examples validate the evidence format only; the separate fresh
  consumer smoke run and real Collector run establish runtime replacement proof.

  @TRP-01 @TRC-11 @phase7
  Scenario: TRP-01 Recorded trace output preserves spans and correlated logs
    Given the trace Collector verification fixture
    When I verify its trace records and correlated log
    Then the trace conformance verifier accepts the relationships

  @TRP-02 @TRC-03 @TRC-10 @phase7
  Scenario Outline: TRP-02 Incorrect record-scoped evidence is rejected
    Given the trace Collector verification fixture
    When I alter its "<field>" evidence
    Then the trace conformance verifier rejects the changed output

    Examples:
      | field            |
      | child status     |
      | log span ID      |
      | instrumentation  |

  @TRP-03 @TRC-11 @phase7
  Scenario: TRP-03 Logs and metrics alone cannot complete the three-signal run
    When I run conformance with only logs and metrics before command failure
    Then conformance fails after checking for traces and cleans up its container

  @TRP-04 @TRC-11 @phase7
  Scenario: TRP-04 Validate a complete replacement evidence report
    Given a synthetic replacement report matching the fresh consumer report format
    When I validate the replacement evidence report
    Then the report validator accepts its structure without claiming a real smoke run

  @TRP-04 @TRC-11 @phase7
  Scenario: TRP-04 Reject a report retaining the canonical exporter
    Given a synthetic replacement report matching the fresh consumer report format
    When the report says the canonical exporter is present
    Then the replacement report validator rejects the evidence
