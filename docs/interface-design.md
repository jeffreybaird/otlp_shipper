# Public interface design

The interface is what another Elixir application calls. Prioritize clear inputs,
return values, failure semantics, and lifecycle over a large API surface.

Before adding a public function, specify its purpose, arguments/types, defaults,
return values, side effects, and acceptance tests. Distinguish validation from
transport failures. Validate external input without creating atoms from arbitrary
strings. Use documented options instead of reading a caller's environment implicitly.

If processes are needed, show a consumer supervision-tree example and explain who
starts the process, how it is named, and what restart/shutdown means. If no processes
are needed, make ordinary function calls sufficient. Runtime behavior must not rely
on the package's development configuration being loaded by a consumer.

For an asynchronous API, say whether success means accepted, queued, or delivered.
Document what a flush waits for, timeout behavior, overload behavior, and what can
be lost or duplicated. Do not promise exactly-once delivery without evidence.

Treat exported functions/types, configuration keys/defaults, error shapes, child
specifications, and documented events as compatibility surfaces. Review their
changes explicitly. Deprecate with migration guidance when practical; record
intentional breaking changes in release notes.

The current `formats/0` and `greet/1,2` are scaffold examples. Resolve PLAN.md's remaining API/naming decisions before replacing them; do not advertise them as OTLP support.

Use semantic versions: breaking changes in the initial `0.x` series increment the
minor version; document the migration even before `1.0`. See the official
[Hex publishing guide](https://hex.pm/docs/publish).
