Feature: Package dependency requirements exclude vulnerable mint and hpax releases
  mint 1.10.2 fixes EEF-CVE-2026-94194, EEF-CVE-2026-91043 and EEF-CVE-2026-92103.
  Finch admits vulnerable mint releases, so the package declares the floor directly.

  Scenario: DEPS-01 mint is a direct requirement for every consumer environment
    Given the package's declared "mint" dependency
    Then the declared dependency is required in every environment at runtime

  Scenario Outline: DEPS-02 the mint requirement rejects versions affected by the advisories
    Given the package's declared "mint" dependency
    When I check the declared requirement against version "<version>"
    Then the declared requirement rejects that version

    Examples:
      | version |
      | 1.9.3   |
      | 1.10.0  |
      | 1.10.1  |
      | 2.0.0   |

  Scenario Outline: DEPS-03 the mint requirement accepts patched compatible 1.x releases
    Given the package's declared "mint" dependency
    When I check the declared requirement against version "<version>"
    Then the declared requirement accepts that version

    Examples:
      | version |
      | 1.10.2  |
      | 1.10.3  |
      | 1.11.0  |
      | 1.14.5  |

  # hpax 1.0.4 fixes EEF-CVE-2026-58226 (affected >= 0.1.1 and < 1.0.4).
  # mint 1.10.2 still admits vulnerable hpax releases, so the floor is declared directly.

  Scenario: DEPS-04 hpax is a direct requirement for every consumer environment
    Given the package's declared "hpax" dependency
    Then the declared dependency is required in every environment at runtime

  Scenario Outline: DEPS-05 the hpax requirement rejects versions affected by the advisory
    Given the package's declared "hpax" dependency
    When I check the declared requirement against version "<version>"
    Then the declared requirement rejects that version

    Examples:
      | version |
      | 0.1.1   |
      | 0.2.0   |
      | 1.0.0   |
      | 1.0.3   |
      | 2.0.0   |

  Scenario Outline: DEPS-06 the hpax requirement accepts patched compatible 1.x releases
    Given the package's declared "hpax" dependency
    When I check the declared requirement against version "<version>"
    Then the declared requirement accepts that version

    Examples:
      | version |
      | 1.0.4   |
      | 1.1.0   |
      | 1.3.2   |
