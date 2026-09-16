Feature: Independent agent workflow with human-controlled verification changes
  The orchestrator coordinates specifications, tests, implementation and review.
  Cucumber/Gherkin records acceptance; Python tests execute hook behavior.

  @GUARD-01
  Scenario: A test becomes protected immediately after creation
    Given a test file does not exist
    When the spec writer creates it through apply_patch
    Then creation is allowed
    And every subsequent edit requires human approval

  @GUARD-02
  Scenario: Existing verification assets cannot be changed by an agent
    Given an existing test, helper, fixture, scenario or doctest
    When an agent tries to update, rename or delete it
    Then the hook denies the call before it executes
    And requests a human-reviewed patch applied outside the agent

  @GUARD-03
  Scenario: Verification rules cannot be weakened
    Given the project has lint, formatting and verification standards
    When an agent edits their configuration or adds a recognized suppression
    Then the hook denies the call

  @GUARD-04
  Scenario: Alternate write paths do not silently bypass the guard
    Given the hook receives an opaque tool or unclassified shell command
    When the operation could mutate protected files
    Then the hook denies the call

  @GUARD-05
  Scenario: Ordinary implementation and verification remain possible
    Given a production file without doctests or protected configuration
    When the implementer submits an ordinary patch
    Then the hook allows it
    And documented verification commands remain allowed

  @LOOP-01
  Scenario: A reviewer finds missing behavior
    Given the runner has reported green for the current feature
    When the reviewer finds an uncovered acceptance requirement
    Then the orchestrator assigns that behavior to the spec writer
    And the runner establishes red for a new regression test
    And the implementer fixes the behavior
    And the runner verifies green and applicable full checks
    And the orchestrator updates the PR
    And the reviewer inspects the new revision before satisfaction
