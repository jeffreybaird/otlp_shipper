# Tooling acceptance specification verified through CLI and workflow inspection.
# These scenarios do not add runtime Cucumber steps or change package behavior.
Feature: Require strict Credo analysis during development and CI
  Developers fix static analysis findings without suppressing diagnostics.
  Consumers do not need development analysis tools in production releases.

  @CRD-01
  Scenario: CRD-01 Strict analysis passes after baseline findings are fixed
    Given Credo is installed as a development and test dependency
    And the baseline strict analysis findings have been recorded
    When the corrected source is checked with "mix credo --strict"
    Then the command exits successfully with no reported findings
    And the corrections preserve existing public behavior and test assertions

  @CRD-02
  Scenario: CRD-02 A strict analysis finding blocks the required check
    Given a disposable copy of the project containing a known enabled Credo violation
    When the required strict Credo command runs against that copy
    Then the command exits unsuccessfully and identifies the violation
    And the pipeline does not mask that exit status or continue on error
    And the disposable violation does not remain in the working project

  @CRD-03
  Scenario: CRD-03 Require Credo alongside the existing verification tools
    Given the CI workflow and documented development verification commands
    When their static analysis and test checks are inspected
    Then strict Credo is a required check
    And Dialyzer, formatting, compilation, tests, and existing acceptance checks remain required
    And no rule suppression, source exclusion, or skipped check is introduced to conceal baseline findings

  @CRD-04
  Scenario: CRD-04 Keep analysis tooling out of production releases
    Given a fresh consumer built from the candidate package archive
    When its production dependency graph and release are inspected
    Then Credo is not a required consumer dependency or release application
    And the consumer release still exports the expected logs and metrics
