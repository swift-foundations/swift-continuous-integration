# swift-continuous-integration

The vendor-neutral continuous-integration domain: plans, requirements,
verdicts and execution semantics.

`ContinuousIntegration` is the sole owner of the generic CI domain. It
models how a verification run is planned (tier classification, platform
filtering, leg selection, gating derivation), what each participant is
required to have done, and how an aggregate verdict over the run is
formed. Nothing GitHub-specific or Institute-specific lives here: the
relation to GitHub's CI platform and the Institute's CI policy belong to
their own packages.

## Products

- **Continuous Integration** — the `ContinuousIntegration` namespace:
  `Plan`, `Requirement`, `Leg`, `Tier`, `AggregateVerdict`.
