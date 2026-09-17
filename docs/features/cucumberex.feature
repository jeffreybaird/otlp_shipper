Feature: Resolve shipper configuration through the public API
  Consumers can configure each implemented signal without global environment state.
  Unsupported protocols and invalid endpoints return specific errors.

  Background:
    Given an isolated configuration for service "checkout"

  @CUC-001
  Scenario: Configure logs with an exact endpoint and resource
    Given the explicit endpoint "https://collector.example/custom/logs"
    When I resolve configuration for "logs"
    Then the configured signal is "logs"
    And the configured endpoint is "https://collector.example/custom/logs"
    And the configured service name is "checkout"

  @CUC-002
  Scenario: Configure metrics with an exact endpoint and resource
    Given the explicit endpoint "https://collector.example/custom/metrics"
    When I resolve configuration for "metrics"
    Then the configured signal is "metrics"
    And the configured endpoint is "https://collector.example/custom/metrics"
    And the configured service name is "checkout"

  @CUC-003
  Scenario: Reject a protocol the HTTP protobuf exporter does not support
    Given the environment option "OTEL_EXPORTER_OTLP_PROTOCOL" is "grpc"
    When I resolve configuration for "logs"
    Then configuration fails with the unsupported protocol error

  @CUC-004
  Scenario: Reject an endpoint that cannot use HTTP transport
    Given the explicit endpoint "ftp://collector.example/logs"
    When I resolve configuration for "logs"
    Then configuration fails with the invalid endpoint error
