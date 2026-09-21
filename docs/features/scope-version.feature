Feature: Instrumentation scope version follows the installed shipper
  Logs and metrics identify the installed otlp_shipper application version.
  Trace scopes remain owned by their original instrumentation.

  Scenario Outline: SCOPE-01 logs and metrics report the application version
    Given the installed shipper application version
    When I encode a shipper "<signal>" scope
    Then the encoded scope identifies the installed shipper version

    Examples:
      | signal  |
      | logs    |
      | metrics |

  Scenario: SCOPE-02 trace scope identity remains authoritative
    Given a trace scope named "consumer.instrumentation" at version "7.8.9"
    When I encode that original trace scope
    Then the original trace scope name and version are preserved

  Scenario: SCOPE-03 Collector conformance follows the current package
    Given Collector evidence using the installed shipper scope version
    When I validate the shipper scope evidence
    Then the shipper scope evidence is accepted

  Scenario: SCOPE-04 Collector conformance rejects another package version
    Given Collector evidence using the installed shipper scope version
    When I replace the shipper scope version with an incorrect version
    Then the shipper scope evidence is rejected
