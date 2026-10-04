Feature: Consumers resolve a patched Mint transport
  The package must enforce its Mint security floor without relying on the
  repository lockfile, which Hex does not distribute to consumers.

  Scenario: DEP-01 Mint is required in production
    Given the shipper package dependency declarations
    Then Mint is a required production Hex dependency

  Scenario Outline: DEP-02 Mint versions respect the security floor
    Given the shipper package dependency declarations
    Then Mint version "<version>" is "<result>" by the package requirement

    Examples:
      | version | result   |
      | 1.10.1  | rejected |
      | 1.10.2  | accepted |
      | 1.11.0  | accepted |
      | 2.0.0   | rejected |

  # Executable steps: features/step_definitions/package_dependencies_steps.ex
  # Unit boundaries: test/otlp_shipper/package_dependencies_test.exs
