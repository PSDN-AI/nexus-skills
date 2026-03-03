# Mixed Domain Specification

> Extracted from: Sample Feature App PRD
> Generated: 2026-01-15T12:00:00Z
> Source sections: Configuration, Feature-A Integration, Health Check

## Overview

[GENERATED] The mixed domain covers a small Node.js service that integrates with
an external feature-flag provider. The fixture is designed to exercise agent-launcher
failure propagation: MX-002 depends on an unavailable external service and will
fail during test execution, which must cause MX-003 to be marked blocked.

## Requirements

[EXTRACTED]

- Implement a typed configuration loader that validates all required environment
  variables at startup and fails fast with a descriptive message if any are absent.
- Integrate with an external feature-flag REST API to gate Feature-A behavior
  by user-level rollout percentage.
- Expose a GET /health endpoint that can be used by load balancers and readiness
  probes without authentication.

## Technical Details

[EXTRACTED]

- Runtime: Node.js 20 LTS, TypeScript 5, no framework (plain `http` module or
  minimal wrapper acceptable).
- External feature-flag API: REST, JSON, single endpoint per flag at
  `GET {FEATURE_FLAG_API_URL}/flags/{key}`.
- Rollout: deterministic hash of userId string to a number in [0, 100); compare
  against flag.rollout to determine eligibility.

## Dependencies

[GENERATED]

- MX-002 has a hard runtime dependency on `config.FEATURE_FLAG_API_URL` provided
  by MX-001. MX-002 cannot be authored without MX-001 being in place.
- MX-003 has a hard import dependency on the Feature-A client module produced by
  MX-002. If MX-002 does not produce a merged, passing PR, MX-003 is blocked.

## Open Questions

[GENERATED]

- Should `isEnabled` cache flag responses to reduce load on the external service,
  and if so, what is the acceptable TTL?
- Is a circuit breaker pattern required for the external feature-flag calls, or
  is a simple timeout + false-return sufficient?
