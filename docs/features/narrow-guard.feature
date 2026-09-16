Feature: Narrow test contract and static analysis review
  The hook identifies review candidates without claiming to infer intent.
  Context reminders allow legitimate user-requested contract changes to proceed.

  Scenario: NG-01 Unrelated tools and ordinary commands pass
    Given a research tool, agent tool, or ordinary shell command
    When the hook evaluates the operation
    Then it emits no decision or reminder

  Scenario: NG-02 Ordinary file changes pass
    Given production code, documentation, or unrelated configuration
    When an ordinary edit preserves tests and analysis
    Then the hook emits no decision or reminder

  Scenario: NG-03 Additional coverage and cosmetic changes pass
    Given an existing test file
    When assertions are added or formatting or its filename changes
    Then the hook emits no decision or reminder

  Scenario: NG-04 Existing test contract changes receive contextual review
    Given an existing test, fixture, helper, or doctest
    When its contract is changed, removed, or skipped
    Then the hook reminds the agent to fix defective code instead of hiding failures
    And the reminder permits legitimate user-required contract changes
    And the reminder does not deny the operation or claim inferred intent

  Scenario: NG-05 Potential analysis weakening receives contextual review
    Given executable source or analyzer configuration
    When a suppression, exclusion, or removal of a required analysis step is proposed
    Then the hook emits an analysis review reminder

  Scenario: NG-06 Explicit analyzer exit status masking is denied
    Given a command that runs static analysis
    When the command explicitly masks analysis failure
    Then the hook denies the operation with a reason

  Scenario: NG-07 Mentioning suppression syntax does not trigger review
    Given documentation or a test string literal containing suppression syntax
    When the text is added
    Then the hook emits no decision or reminder

  Scenario: NG-08 CLI preserves host output contract
    Given a serialized PreToolUse event
    When the hook executable reads the event
    Then unrelated events produce no output
    And review events produce additionalContext without a denial
    And explicit analyzer bypass produces a supported denial

  Scenario: NG-09 Hook matcher targets supported mutation tools
    Given the hook configuration
    When the host selects PreToolUse tools
    Then only canonical Bash and apply_patch tool names match
