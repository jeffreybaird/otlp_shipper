defmodule Mix.Tasks.Compile.OtlpProtos do
  @moduledoc false
  use Mix.Task.Compiler

  @modules [:otlp_shipper_logs_service, :otlp_shipper_metrics_service]

  @impl true
  def run(_args) do
    Mix.ensure_application!(:syntax_tools)
    root = Path.expand("priv/proto")
    sources = Path.wildcard(Path.join(root, "**/*.proto"))

    inputs = [
      File.read!(__ENV__.file),
      System.otp_release(),
      System.version(),
      :gpb_compile.module_info(:md5) | Enum.map(sources, &File.read!/1)
    ]

    digest = :crypto.hash(:sha256, inputs)
    [manifest] = manifests()
    output = Mix.Project.compile_path()

    if File.read(manifest) == {:ok, digest} and
         Enum.all?(@modules, &File.exists?(beam_path(output, &1))) do
      {:noop, []}
    else
      File.mkdir_p!(output)
      File.mkdir_p!(Path.dirname(manifest))

      Enum.each(Enum.filter(sources, &String.ends_with?(&1, "_service.proto")), fn source ->
        options = [
          :binary,
          :maps,
          :use_packages,
          :strings_as_binaries,
          :type_specs,
          {:erlc_compile_options, ~c"debug_info"},
          {:module_name_prefix, ~c"otlp_shipper_"},
          {:i, String.to_charlist(root)}
        ]

        case :gpb_compile.file(String.to_charlist(source), options) do
          {:ok, module, binary} ->
            path = beam_path(output, module)
            File.write!(path, binary)
            {:module, ^module} = :code.load_binary(module, String.to_charlist(path), binary)

          error ->
            Mix.raise("OTLP protobuf generation failed: #{inspect(error)}")
        end
      end)

      File.write!(manifest, digest)
      {:ok, []}
    end
  end

  @impl true
  def manifests, do: [Path.join(Mix.Project.manifest_path(), "compile.otlp_protos")]

  @impl true
  def clean do
    Enum.each(manifests(), &File.rm/1)
    Enum.each(@modules, &File.rm(beam_path(Mix.Project.compile_path(), &1)))
    :ok
  end

  defp beam_path(output, module), do: Path.join(output, "#{module}.beam")
end
