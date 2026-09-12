# otlp_shipper

TODO: one sentence describing otlp_shipper.

## Develop

    mix deps.get
    mix test

## Publish

Fill in `:licenses` and `:links` in `mix.exs`, then:

    mix hex.publish

## Pipeline

Every push runs `.github/workflows/ci.yml` (or `.gitea/workflows/ci.yml`):
format check, compile with warnings as errors, and the test suite.

This project provisions no infrastructure — no droplet, no DNS, no database.
It was created with `bootstrap.sh --no-droplet`.

The BEAM versions are pinned in `.tool-versions`, which CI reads directly.
