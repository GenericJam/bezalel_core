%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      strict: true,
      plugins: [{ExSlop, []}],
      checks: %{
        disabled: [
          {Credo.Check.Readability.SinglePipe, []}
        ]
      }
    }
  ]
}
