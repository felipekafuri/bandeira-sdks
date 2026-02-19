# PHP SDK Design (Bandeira)

**Date:** 2026-02-19  
**Status:** Approved

## Goals

- Add an official PHP SDK in this monorepo under `php/`.
- Keep behavior parity with existing Go/JS/Python SDKs.
- Provide first-class Laravel integration in the same package.
- Add CI and publish workflows following existing repo conventions.

## Architecture

- Package layout:
  - `php/src/` for framework-agnostic core SDK.
  - `php/src/Laravel/` for optional Laravel integration.
  - `php/tests/` for core and Laravel tests.
- Composer package name: `bandeira/bandeira`.
- Core SDK remains independent from Laravel internals.

## Core API and Data Flow

- Public API:
  - `Config(url, token, pollInterval=15, httpClient?, requestFactory?)`
  - `Context(userId="", sessionId="", remoteAddress="", properties=[])`
  - `Client::isEnabled(string $flag, ?Context $ctx = null): bool`
  - `Client::allFlags(): array<string,bool>`
  - `Client::refresh(): void`
- Refresh model (request-safe on-demand):
  - No background polling worker.
  - Cache refresh is attempted when data is stale (`pollInterval` TTL).
  - On refresh failure, keep last-known cache (fail soft).
- Fetch:
  - `GET {url}/api/v1/flags`
  - `Authorization: Bearer {token}`
  - Atomically replace local flag map on success.
- Evaluation parity:
  - Strategy OR logic, constraint AND logic.
  - Unknown strategy is fail-open after constraints pass.
  - Unknown operator returns false.
  - Match helpers/semantics from existing SDKs:
    - `splitMulti` (comma/newline)
    - FNV-1a hash `% 100`
    - case-insensitive constraints
    - RFC3339 date comparisons

## Laravel Integration

- Optional classes under `src/Laravel/`:
  - `BandeiraServiceProvider`
  - `Bandeira` facade
  - `ContextResolver` contract + default resolver
- Service provider responsibilities:
  - Merge/publish `config/bandeira.php`
  - Register `Client` singleton from config/env
  - Register default context resolver
- DX behavior:
  - Out-of-the-box request/auth context support.
  - `isEnabledForCurrentRequest(string $flag): bool` convenience path.
  - Explicit context API remains available for jobs/CLI.

## Testing and Quality

- Core parity tests using shared `testdata/flags.json`:
  - basic toggles
  - `default`, `userWithId`, `gradualRollout`, `remoteAddress`
  - constraints: `IN`, `NOT_IN`, `STR_*`, `NUM_*`, `DATE_*`
  - inversion/case-insensitive
  - multi-strategy OR and constrained rollout
- Validation tests for missing URL/token.
- Refresh behavior tests:
  - stale refresh success
  - stale refresh failure with last-known cache
- Laravel tests (Orchestra Testbench):
  - provider registration, config wiring, facade, context resolver

## Workflows and Release

- Add `.github/workflows/php.yml`:
  - run tests on push/PR for `php/**` and `testdata/**`
  - publish on tags matching `php/v*`
- Publish target: Packagist-compatible release flow.

## Documentation and Versioning

- Update root `README.md` with PHP SDK row and quick start.
- Add `php/README.md` with standalone and Laravel usage.
- Initial package version: `0.1.0`.
- PR scope excludes changes to behavior in Go/JS/Python.

