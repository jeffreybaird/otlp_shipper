defmodule OtlpShipper.Acceptance.PackageDependenciesSteps do
  @moduledoc false
  use Cucumberex.DSL

  import ExUnit.Assertions

  given_("the shipper package dependency declarations", fn world ->
    dependencies = OtlpShipper.MixProject.project()[:deps]
    {requirement, options} = direct_dependency(dependencies, :mint, "Mint")

    Map.merge(world, %{
      dependencies: dependencies,
      mint_requirement: requirement,
      mint_options: options
    })
  end)

  then_("Mint is a required production Hex dependency", fn world ->
    refute Keyword.get(world.mint_options, :optional, false)
    assert :prod in List.wrap(Keyword.get(world.mint_options, :only, :prod))
    refute Keyword.has_key?(world.mint_options, :path)
    refute Keyword.has_key?(world.mint_options, :git)
    refute Keyword.has_key?(world.mint_options, :github)
    assert Keyword.get(world.mint_options, :hex, :mint) == :mint
    world
  end)

  then_("Mint version {string} is {string} by the package requirement", fn world,
                                                                           version,
                                                                           result ->
    assert Version.match?(version, world.mint_requirement) == (result == "accepted")
    world
  end)

  then_("HPAX is a required production Hex dependency", fn world ->
    {_requirement, options} = direct_dependency(world.dependencies, :hpax, "HPAX")

    refute Keyword.get(options, :optional, false)
    assert :prod in List.wrap(Keyword.get(options, :only, :prod))
    refute Keyword.has_key?(options, :path)
    refute Keyword.has_key?(options, :git)
    refute Keyword.has_key?(options, :github)
    assert Keyword.get(options, :hex, :hpax) == :hpax
    world
  end)

  then_("HPAX version {string} is {string} by the package requirement", fn world,
                                                                           version,
                                                                           result ->
    {requirement, _options} = direct_dependency(world.dependencies, :hpax, "HPAX")

    assert Version.match?(version, requirement) == (result == "accepted")
    world
  end)

  defp direct_dependency(dependencies, app, label) do
    dependency = List.keyfind(dependencies, app, 0)

    assert dependency,
           "#{label} must be declared directly so Hex consumers inherit its security floor"

    case dependency do
      {^app, requirement} -> {requirement, []}
      {^app, requirement, options} -> {requirement, options}
    end
  end
end
