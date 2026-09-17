%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{
        included: [
          "lib/",
          "test/",
          "features/",
          "mix/",
          "config/",
          "priv/conformance/",
          "mix.exs"
        ]
      }
    }
  ]
}
