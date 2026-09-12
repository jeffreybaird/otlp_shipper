defmodule OtlpShipper.ResourceTest do
  use ExUnit.Case, async: true
  alias OtlpShipper.Resource
  doctest Resource

  test "requires a nonempty string service identity" do
    for opts <- [
          [],
          [service_name: ""],
          [service_name: "  "],
          [service_name: 1],
          [service_name: <<255>>]
        ] do
      assert {:error, :service_name_required} = Resource.new(opts)
    end

    for opts <- [[resource: 1], [resource: %{1 => "bad"}], %{}] do
      assert {:error, :invalid_resource} = Resource.new(opts)
    end

    assert {:error, :invalid_resource} =
             Resource.new([], %{"OTEL_RESOURCE_ATTRIBUTES" => "missing_equals"})
  end

  test "explicit identity wins over resource, service environment, and attribute environment" do
    env = %{
      "OTEL_RESOURCE_ATTRIBUTES" => "service.name=attributes,region=us%2Ceast",
      "OTEL_SERVICE_NAME" => "environment"
    }

    assert {:ok, resource} = Resource.new([], env)
    assert attribute(resource, "service.name") == "environment"
    assert attribute(resource, "region") == "us,east"
    assert {:ok, resource} = Resource.new([resource: %{"service.name" => "resource"}], env)
    assert attribute(resource, "service.name") == "resource"

    assert {:ok, resource} =
             Resource.new(
               [
                 service_name: "explicit",
                 service_version: "1.0",
                 service_instance_id: "instance"
               ],
               env
             )

    assert attribute(resource, "service.name") == "explicit"
    assert attribute(resource, "service.version") == "1.0"
    assert attribute(resource, "service.instance.id") == "instance"
  end

  defp attribute(resource, key) do
    %{value: %{value: {:string_value, value}}} = Enum.find(resource.attributes, &(&1.key == key))
    value
  end
end
