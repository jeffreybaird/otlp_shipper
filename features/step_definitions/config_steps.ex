defmodule OtlpShipper.Acceptance.ConfigSteps do
  @moduledoc false
  use Cucumberex.DSL

  import ExUnit.Assertions

  alias OtlpShipper.Config

  given_("an isolated configuration for service {string}", fn world, service_name ->
    Map.merge(world, %{options: [service_name: service_name], environment: %{}})
  end)

  given_("the explicit endpoint {string}", fn world, endpoint ->
    Map.update!(world, :options, &Keyword.put(&1, :endpoint, endpoint))
  end)

  given_("the environment option {string} is {string}", fn world, name, value ->
    Map.update!(world, :environment, &Map.put(&1, name, value))
  end)

  when_("I resolve configuration for {string}", fn world, signal ->
    result = Config.new(signal_atom(signal), world.options, world.environment)
    Map.put(world, :result, result)
  end)

  then_("the configured signal is {string}", fn world, signal ->
    assert {:ok, config} = world.result
    assert config.signal == signal_atom(signal)
    world
  end)

  then_("the configured endpoint is {string}", fn world, endpoint ->
    assert {:ok, config} = world.result
    assert config.endpoint == endpoint
    world
  end)

  then_("the configured service name is {string}", fn world, service_name ->
    assert {:ok, config} = world.result

    assert %{key: "service.name", value: %{value: {:string_value, service_name}}} in config.resource.attributes

    world
  end)

  then_("configuration fails with the unsupported protocol error", fn world ->
    assert world.result == {:error, :unsupported_protocol}
    world
  end)

  then_("configuration fails with the invalid endpoint error", fn world ->
    assert world.result == {:error, :invalid_endpoint}
    world
  end)

  defp signal_atom("logs"), do: :logs
  defp signal_atom("metrics"), do: :metrics
end
