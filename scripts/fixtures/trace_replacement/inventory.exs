# Record build dependency resolution separately from release runtime applications.
dependencies =
  Mix.Dep.load_and_cache()
  |> Enum.map(fn dependency ->
    {:ok, version} = dependency.status
    %{name: Atom.to_string(dependency.app), version: version}
  end)
  |> Enum.sort_by(& &1.name)

File.write!("dependencies.json", :json.encode(dependencies))
