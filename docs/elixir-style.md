# Elixir style

Adapted from Marquee's code style, separation-of-concerns, architecture, testing,
observability, and scalability guidance. Application-specific modules and rules
are not dependencies of this package.

## Functions and modules

Keep one responsibility per function. A description that joins unrelated jobs with
“and” usually signals a split. An operation may still coordinate necessary steps
behind one coherent public contract. Use pattern matching and guards for clear
cases, `with` for a sequence of fallible steps, and `case` for outcome branching.

Use pipes for multistep transformations. Name intermediate values when they are
reused or explain intent. Private functions describe the action: `normalize_options`
or `reject_oversized_batch`, rather than `process_data`. Keep aliases local and
abstractions proportional to real complexity.

Core modules own rules; transport adapters and process callbacks own their external
boundaries. A caller should not need to recreate business logic in a Mix task or
Phoenix wrapper. Do not add a GenServer merely to organize functions.

## Public documentation

Use `@moduledoc` for purpose and lifecycle, `@doc` for consumer-facing functions,
`@spec` for public contracts, and `@typedoc` for exposed types. Include a runnable
happy-path doctest for every public function with deterministic, pure behavior.

Effectful functions use isolated ExUnit tests instead of doctests that contact a
service. Required callbacks use `@impl true` and callback/integration tests;
internal exported helpers can use `@doc false` with a stated internal role. Do not
hide an intended public API to avoid documenting or testing it.

Document errors, defaults, option units, side effects, and constraints. Examples
must compile against the implemented API; never present planned functions as usable.

## Results and errors

Use direct values for infallible transformations. For fallible public operations,
use a documented success value and stable tagged error reasons. Illustrative shapes:

```elixir
{:ok, value}
{:error, :invalid_options, %{option: :timeout}}
{:error, :timeout}
{:error, :transport, %{reason: :closed}}
```

These are style examples, not an established `OtlpShipper` error taxonomy. Keep
error details bounded and free of secrets. Avoid arbitrary exception terms in a
public contract when normalized data suffices. Never use a human-readable string
as the reason callers must branch on.

Honor OTP/behaviour callback return contracts exactly; normalize dependency errors
at the public boundary. Reserve exceptions for programmer errors or documented bang
functions. Do not rescue everything into apparent success or wrap every pure return
value in `{:ok, ...}`.

## Side effects and diagnostics

Use small client boundaries; adopt behaviours and Mox only when an actual boundary
benefits from them. Pass operation inputs explicitly. Avoid process-dictionary
request context and global configuration mutation as hidden dependencies.

Keep Logger messages stable and put varying values in metadata. Include correlation
context only when available; there is no mandatory tenant ID. Redact credentials and
payloads. Instrumentation must preserve operation results and avoid recursive export.
Do not copy Marquee's requirement to trace every mutation into a telemetry transport
without first addressing feedback loops.
