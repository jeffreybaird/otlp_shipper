defmodule OtlpShipper.PackageDependenciesTest do
  use ExUnit.Case, async: true

  test "DEP-01 Mint is a required production Hex dependency" do
    {_requirement, options} = mint_dependency()

    refute Keyword.get(options, :optional, false)
    assert :prod in List.wrap(Keyword.get(options, :only, :prod))
    refute Keyword.has_key?(options, :path)
    refute Keyword.has_key?(options, :git)
    refute Keyword.has_key?(options, :github)
    assert Keyword.get(options, :hex, :mint) == :mint
  end

  test "DEP-02 Mint requirement excludes vulnerable releases and allows compatible updates" do
    {requirement, _options} = mint_dependency()

    refute Version.match?("1.10.1", requirement)
    assert Version.match?("1.10.2", requirement)
    assert Version.match?("1.11.0", requirement)
    refute Version.match?("2.0.0", requirement)
  end

  test "DEP-03 HPAX is a required production Hex dependency" do
    {_requirement, options} = hpax_dependency()

    refute Keyword.get(options, :optional, false)
    assert :prod in List.wrap(Keyword.get(options, :only, :prod))
    refute Keyword.has_key?(options, :path)
    refute Keyword.has_key?(options, :git)
    refute Keyword.has_key?(options, :github)
    assert Keyword.get(options, :hex, :hpax) == :hpax
  end

  test "DEP-04 HPAX requirement excludes vulnerable releases and allows compatible updates" do
    {requirement, _options} = hpax_dependency()

    refute Version.match?("0.2.0", requirement)
    refute Version.match?("1.0.3", requirement)
    assert Version.match?("1.0.4", requirement)
    assert Version.match?("1.1.0", requirement)
    refute Version.match?("2.0.0", requirement)
  end

  defp mint_dependency, do: direct_dependency(:mint, "Mint")

  defp hpax_dependency, do: direct_dependency(:hpax, "HPAX")

  defp direct_dependency(app, label) do
    dependency = List.keyfind(OtlpShipper.MixProject.project()[:deps], app, 0)

    assert dependency,
           "#{label} must be declared directly so Hex consumers inherit its security floor"

    case dependency do
      {^app, requirement} -> {requirement, []}
      {^app, requirement, options} -> {requirement, options}
    end
  end
end
