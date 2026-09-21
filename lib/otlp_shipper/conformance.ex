defmodule OtlpShipper.Conformance do
  @moduledoc false
  alias OtlpShipper.Conformance.{ReplacementReport, TraceOutput}
  # Internal boundary for the opt-in Mix task; no processes start in consumers.
  @image "otel/opentelemetry-collector@sha256:e495787f07dbe432ce763ebaf5bc3d113850e9eee2250ade7a3da6a882d0d69a"

  @doc false
  @spec run(function()) :: :ok | {:error, atom()}
  def run(command \\ &System.cmd/3) do
    if Code.ensure_loaded?(OtlpShipper.TraceExporter) and Code.ensure_loaded?(:otel_tracer) do
      run_collector(command)
    else
      {:error, :tracing_sdk_unavailable}
    end
  end

  # Only the opt-in task invokes Docker; runtime consumers start no processes here.
  defp run_collector(command) do
    name =
      "otlp-shipper-conformance-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    priv = :otlp_shipper |> :code.priv_dir() |> to_string() |> Path.expand()
    Mix.shell().info("Collector container: #{name}")

    result =
      try do
        with {:ok, _} <-
               execute(
                 command,
                 "docker",
                 [
                   "run",
                   "--detach",
                   "--rm",
                   "--pull=never",
                   "--name",
                   name,
                   "--publish",
                   "127.0.0.1::4318",
                   "--mount",
                   "type=bind,source=#{priv}/conformance/collector.yaml,target=/etc/otelcol/config.yaml,readonly",
                   @image
                 ],
                 []
               ),
             {:ok, address} <- execute(command, "docker", ["port", name, "4318/tcp"], []),
             {:ok, endpoint} <- endpoint(address),
             :ok <- await_output(command, name, &String.contains?(&1, "Everything is ready.")),
             {:ok, _} <-
               execute(
                 command,
                 "mix",
                 ["run", "--no-compile", "--no-start", "#{priv}/conformance/emit.exs", endpoint],
                 env: clean_environment(System.get_env())
               ) do
          await_output(command, name, &(verify(&1) == :ok and verify_traces(&1) == :ok))
        end
      after
        # Cleanup is also attempted when a command raises or the fixture fails.
        case execute(command, "docker", ["rm", "--force", name], []) do
          {:ok, _} -> :ok
          {:error, _} -> Mix.shell().error("Collector cleanup failed; remove container #{name}")
        end
      end

    result
  end

  @doc false
  @spec clean_environment(map()) :: [{String.t(), nil}]
  def clean_environment(env) do
    env |> Map.keys() |> Enum.filter(&String.starts_with?(&1, "OTEL_")) |> Enum.map(&{&1, nil})
  end

  @doc false
  @spec endpoint(String.t()) :: {:ok, String.t()} | {:error, :invalid_docker_port}
  def endpoint(address) do
    case Regex.run(~r/\A127\.0\.0\.1:(\d+)\s*\z/, address) do
      [_, port] -> {:ok, "http://127.0.0.1:#{port}"}
      _ -> {:error, :invalid_docker_port}
    end
  end

  @doc false
  @spec verify(String.t()) :: :ok | {:error, :collector_output_mismatch}
  def verify(output) do
    version = :otlp_shipper |> Application.spec(:vsn) |> to_string()

    logs = [
      "Body: Str(otlp-shipper-conformance-log)",
      "conformance: Bool(true)",
      "SeverityText: notice",
      "SeverityNumber: Info2(10)"
    ]

    metrics = [
      [
        "Name: conformance.events.count",
        "DataType: Sum",
        "IsMonotonic: true",
        "AggregationTemporality: Delta",
        "region: Str(test)",
        "Value: 3"
      ],
      [
        "Name: conformance.events.total",
        "DataType: Sum",
        "IsMonotonic: true",
        "AggregationTemporality: Delta",
        "Value: 21"
      ],
      ["Name: conformance.events.current", "DataType: Gauge", "Value: 12"],
      [
        "Name: conformance.events.histogram",
        "DataType: Histogram",
        "AggregationTemporality: Delta",
        "Count: 3",
        "Sum: 21.000000",
        "Min: 2.000000",
        "Max: 12.000000",
        "ExplicitBounds #0: 5.000000",
        "ExplicitBounds #1: 10.000000",
        "Buckets #0, Count: 1",
        "Buckets #1, Count: 1",
        "Buckets #2, Count: 1"
      ]
    ]

    blocks = Regex.split(~r/^Metric #\d+\n/m, output) |> Enum.drop(1)
    log_blocks = Regex.scan(~r/LogRecord #\d+\n(.*?)(?=\n\t\{)/s, output)

    if contains_lines?(output, [
         "service.name: Str(otlp-shipper-conformance)",
         "InstrumentationScope otlp_shipper #{version}"
       ]) and
         Enum.any?(log_blocks, fn [_, block] -> contains_lines?(block, logs) end) and
         length(blocks) == 4 and
         Enum.all?(metrics, fn expected ->
           Enum.any?(blocks, &contains_lines?(&1, ["Unit: 1" | expected]))
         end) do
      :ok
    else
      {:error, :collector_output_mismatch}
    end
  end

  @doc false
  @spec verify_traces(String.t()) :: :ok | {:error, atom()}
  def verify_traces(output), do: TraceOutput.verify(output)

  @doc false
  @spec verify_replacement_report(map()) :: :ok | {:error, atom()}
  def verify_replacement_report(report), do: ReplacementReport.verify(report)

  defp contains_lines?(output, expected) do
    lines =
      output
      |> String.split("\n")
      |> Enum.map(fn line ->
        line |> String.trim() |> String.replace_prefix("-> ", "")
      end)
      |> MapSet.new()

    Enum.all?(expected, &MapSet.member?(lines, &1))
  end

  defp await_output(command, name, predicate, attempts \\ 60)
  defp await_output(_, _, _, 0), do: {:error, :collector_output_timeout}

  defp await_output(command, name, predicate, attempts) do
    with {:ok, output} <- execute(command, "docker", ["logs", "--tail", "1000", name], []) do
      if predicate.(output) do
        :ok
      else
        Process.sleep(250)
        await_output(command, name, predicate, attempts - 1)
      end
    end
  end

  defp execute(command, executable, args, opts) do
    task = Task.async(fn -> invoke(command, executable, args, opts) end)

    case Task.yield(task, 30_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {:error, :command_timeout}
    end
  end

  defp invoke(command, executable, args, opts) do
    case command.(executable, args, [stderr_to_stdout: true] ++ opts) do
      {output, 0} -> {:ok, output}
      {_output, _status} -> {:error, :command_failed}
    end
  rescue
    _ in ErlangError -> {:error, :command_unavailable}
  end
end
