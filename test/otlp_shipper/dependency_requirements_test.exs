defmodule OtlpShipper.DependencyRequirementsTest do
  use ExUnit.Case, async: true

  # mint 1.10.2 fixes EEF-CVE-2026-94194, EEF-CVE-2026-91043 and EEF-CVE-2026-92103.
  # Finch admits vulnerable mint releases, so the package declares the floor directly.
  @vulnerable_mint ["1.9.3", "1.10.0", "1.10.1"]
  @patched_mint ["1.10.2", "1.10.3", "1.11.0", "1.14.5"]

  # hpax 1.0.4 fixes EEF-CVE-2026-58226 (affected >= 0.1.1 and < 1.0.4). mint 1.10.2
  # still admits vulnerable hpax releases, so the package declares the floor directly.
  @vulnerable_hpax ["0.1.1", "0.2.0", "1.0.0", "1.0.3"]
  @patched_hpax ["1.0.4", "1.1.0", "1.3.2"]

  test "DEPS-01 declares a direct mint requirement for every consumer environment" do
    {requirement, opts} = declared_dependency(:mint)

    assert is_binary(requirement)
    refute Keyword.get(opts, :optional, false)
    refute Keyword.has_key?(opts, :only)
    assert Keyword.get(opts, :runtime, true)
  end

  test "DEPS-02 the mint requirement rejects versions affected by the advisories" do
    {requirement, _opts} = declared_dependency(:mint)

    for version <- @vulnerable_mint do
      refute Version.match?(version, requirement),
             "expected #{inspect(requirement)} to reject mint #{version}"
    end
  end

  test "DEPS-03 the mint requirement accepts patched compatible 1.x releases" do
    {requirement, _opts} = declared_dependency(:mint)

    for version <- @patched_mint do
      assert Version.match?(version, requirement),
             "expected #{inspect(requirement)} to accept mint #{version}"
    end

    refute Version.match?("2.0.0", requirement)
  end

  test "DEPS-04 declares a direct hpax requirement for every consumer environment" do
    {requirement, opts} = declared_dependency(:hpax)

    assert is_binary(requirement)
    refute Keyword.get(opts, :optional, false)
    refute Keyword.has_key?(opts, :only)
    assert Keyword.get(opts, :runtime, true)
  end

  test "DEPS-05 the hpax requirement rejects versions affected by the advisory" do
    {requirement, _opts} = declared_dependency(:hpax)

    for version <- @vulnerable_hpax ++ ["2.0.0"] do
      refute Version.match?(version, requirement),
             "expected #{inspect(requirement)} to reject hpax #{version}"
    end
  end

  test "DEPS-06 the hpax requirement accepts patched compatible 1.x releases" do
    {requirement, _opts} = declared_dependency(:hpax)

    for version <- @patched_hpax do
      assert Version.match?(version, requirement),
             "expected #{inspect(requirement)} to accept hpax #{version}"
    end
  end

  defp declared_dependency(name) do
    deps = Mix.Project.config()[:deps]

    case Enum.find(deps, &(elem(&1, 0) == name)) do
      {^name, requirement} when is_binary(requirement) -> {requirement, []}
      {^name, requirement, opts} when is_binary(requirement) -> {requirement, opts}
      other -> flunk("expected a direct #{name} requirement, got: #{inspect(other)}")
    end
  end
end
