defmodule OtlpShipper.Acceptance.DependencyRequirementsSteps do
  @moduledoc false
  use Cucumberex.DSL

  import ExUnit.Assertions

  given_("the package's declared {string} dependency", fn world, name ->
    {requirement, opts} = declared_dependency(String.to_existing_atom(name))
    Map.merge(world, %{dependency_requirement: requirement, dependency_opts: opts})
  end)

  then_("the declared dependency is required in every environment at runtime", fn world ->
    opts = world.dependency_opts
    refute Keyword.get(opts, :optional, false)
    refute Keyword.has_key?(opts, :only)
    assert Keyword.get(opts, :runtime, true)
    world
  end)

  when_("I check the declared requirement against version {string}", fn world, version ->
    Map.merge(world, %{
      checked_version: version,
      version_matches: Version.match?(version, world.dependency_requirement)
    })
  end)

  then_("the declared requirement rejects that version", fn world ->
    refute world.version_matches,
           "expected #{inspect(world.dependency_requirement)} to reject #{world.checked_version}"

    world
  end)

  then_("the declared requirement accepts that version", fn world ->
    assert world.version_matches,
           "expected #{inspect(world.dependency_requirement)} to accept #{world.checked_version}"

    world
  end)

  defp declared_dependency(name) do
    deps = Mix.Project.config()[:deps]

    case Enum.find(deps, &(elem(&1, 0) == name)) do
      {^name, requirement} when is_binary(requirement) -> {requirement, []}
      {^name, requirement, opts} when is_binary(requirement) -> {requirement, opts}
      other -> flunk("expected a direct #{name} requirement, got: #{inspect(other)}")
    end
  end
end
