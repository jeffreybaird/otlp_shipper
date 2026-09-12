# 0.1.0 candidate evidence

Preparation date: September 12, 2026. This document records local preparation,
not a published version. Publication prerequisites are in [readiness.md](readiness.md).

Local validation passed on Elixir 1.19.5 / OTP 29.0.1: formatting, warnings-as-errors
compilation, 91 tests and 19 doctests, Dialyzer, ExDoc, and Hex retirement audit.
Real Collector 0.160.0 passed gzip logs and all four metric types. Fresh production
release delivery passed with resolved and minimum dependencies, without runtime
gpb, with tracing absent and minimum optional API present. API 1.3.0 emits an
upstream `link/2` warning on OTP 29; use API 1.5.0 there.

The reviewed archive checksum, source revision, local publish dry run, and final
CI evidence are recorded below when the candidate is sealed. Until then, use this
as a check log, not as approval of a specific release artifact.
