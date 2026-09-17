Feature: Stop pending tool calls when guard execution fails
  The narrow test and static-analysis classifier retains its existing scope.
  Its deadline wrapper returns explicit denial when inspection cannot complete.
  This Python tooling specification is mapped to Python tests, not CucumberEx.

  Scenario: GD-01 Preserve successful guard responses
    Given a guard worker receives the original tool event
    When it exits successfully with empty output, a valid reminder, or a valid denial
    Then the wrapper preserves the response unchanged
    And stderr alone does not convert success into denial

  Scenario: GD-02 Deny failed or invalid inspection
    Given a guard worker cannot start, exits nonzero, or returns invalid output
    When the wrapper handles the result
    Then it explicitly denies the pending tool call
    And the denial does not expose event input or worker output

  Scenario: GD-03 Bound classifier execution
    Given a guard worker exceeds its five-second default deadline
    When the wrapper detects the timeout
    Then it explicitly denies the pending tool call
    And it kills and reaps the worker

  Scenario: GD-04 Bound input handling
    Given the wrapper is waiting for tool-event input
    When its seven-second entry deadline expires
    Then it explicitly denies the pending tool call before the ten-second host deadline

  Scenario: GD-05 Preserve the narrow classification contract
    Given the wrapper invokes the existing classifier
    When it handles ordinary read-only work or concrete analysis failure masking
    Then ordinary work remains allowed
    And analysis failure masking remains denied

  Scenario: GD-06 Enforce runtime failure handling only after host verification
    Given Codex 0.153.4 can allow a call after an outer hook timeout
    And a runtime source patch is not installed in the current host
    When local wrapper tests pass
    Then those tests do not establish fail-closed host enforcement
    And runtime tests and explicit host installation remain required
