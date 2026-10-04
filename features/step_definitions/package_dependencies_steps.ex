defmodule OtlpShipper.Acceptance.PackageDependenciesSteps do
  @moduledoc false
  use Cucumberex.DSL

  import ExUnit.Assertions

  given_("the shipper package dependency declarations", fn world ->
    dependency = List.keyfind(OtlpShipper.MixProject.project()[:deps], :mint, 0)

    assert dependency,
           "Mint must be declared directly so Hex consumers inherit its security floor"

    {requirement, options} =
      case dependency do
        {:mint, requirement} -> {requirement, []}
        {:mint, requirement, options} -> {requirement, options}
      end

    Map.merge(world, %{mint_requirement: requirement, mint_options: options})
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
end
