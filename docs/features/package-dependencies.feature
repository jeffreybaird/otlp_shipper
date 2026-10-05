Feature: Consumers resolve patched Mint and HPAX transports
  The package must enforce its Mint and HPAX security floors without relying
  on the repository lockfile, which Hex does not distribute to consumers.

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

  Scenario: DEP-03 HPAX is required in production
    Given the shipper package dependency declarations
    Then HPAX is a required production Hex dependency

  Scenario Outline: DEP-04 HPAX versions respect the security floor
    Given the shipper package dependency declarations
    Then HPAX version "<version>" is "<result>" by the package requirement

    Examples:
      | version | result   |
      | 0.2.0   | rejected |
      | 1.0.3   | rejected |
      | 1.0.4   | accepted |
      | 1.1.0   | accepted |
      | 2.0.0   | rejected |

  # Executable steps: features/step_definitions/package_dependencies_steps.ex
  # Unit boundaries: test/otlp_shipper/package_dependencies_test.exs
