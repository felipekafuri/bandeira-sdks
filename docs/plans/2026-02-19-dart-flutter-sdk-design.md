# Dart/Flutter SDK Design

## Context
This repository currently ships official Bandeira SDKs for Go, JavaScript/TypeScript, and Python. They share the same core behavior: poll `/api/v1/flags`, cache flags in memory, and evaluate strategies/constraints locally so runtime checks (`isEnabled`) never do network I/O.

Goal: add a Dart SDK that is Flutter-compatible while preserving parity with existing SDK behavior and test fixtures.

## Objectives
- Provide a pure Dart package that works in Flutter and non-Flutter Dart environments.
- Match strategy/constraint semantics from Go/JS/Python SDKs.
- Support both startup styles:
  - `await client.start()`
  - `await BandeiraClient.create(config)`
- Include CI testing and publishing workflow consistent with existing language SDKs.

## Non-Goals
- Splitting into separate `core` and Flutter wrapper packages in this PR.
- Introducing reactive or stream-first APIs beyond parity requirements.
- Adding server-side targeting features not already in shared fixtures and SDKs.

## Architecture
Package path: `dart/`

Public API (exported from `lib/bandeira.dart`):
- `BandeiraConfig`
- `BandeiraContext`
- `BandeiraClient`

Implementation modules:
- `lib/src/models.dart`
  - API DTOs and context/config types.
- `lib/src/evaluator.dart`
  - Strategy and constraint evaluation logic.
- `lib/src/http_flags_repository.dart`
  - HTTP fetch + JSON decode for `/api/v1/flags`.
- `lib/src/client.dart`
  - Lifecycle (`start`, `create`, `close`), cache management, polling.

Testing:
- `test/bandeira_test.dart`
- Shared fixture usage from `../testdata/flags.json` for parity with JS/Python tests.

## Data Flow
1. Client is constructed with `url`, `token`, optional `pollInterval`, optional custom HTTP client.
2. `start()` and `create()` both perform initial fetch. Initial fetch errors are surfaced immediately.
3. On success, flags are normalized into map keyed by flag name.
4. Background timer polls at interval (default 15 seconds); successful responses atomically replace in-memory cache.
5. `isEnabled(name, [context])` reads cache only and applies evaluation rules.
6. `close()` cancels timer and closes owned HTTP resources.

## Evaluation Rules
### Flag-level behavior
- Missing flag: `false`
- Disabled flag: `false`
- Enabled flag with no strategies: `true`
- Enabled flag with strategies: OR across strategies

### Strategy behavior
- `default`: `true`
- `userWithId`:
  - read `parameters.userIds` (string)
  - split by commas/newlines
  - match against `context.userId`
- `gradualRollout`:
  - parse `parameters.rollout` from number/string
  - `>=100 => true`, `<=0 => false`
  - stickiness from `parameters.stickiness` (`userId`, `sessionId`, or property key)
  - optional `groupId`
  - deterministic bucket via FNV-1a 32-bit hash mod 100
- `remoteAddress`:
  - accept `ips` and legacy `IPs`
  - exact match or prefix entries ending with `.`
- unknown strategy: `true` (fail-open parity)

### Constraints behavior
Each strategy enforces AND across constraints.

Supported operators:
- `IN`, `NOT_IN`
- `STR_CONTAINS`, `STR_STARTS_WITH`, `STR_ENDS_WITH`
- `NUM_EQ`, `NUM_GT`, `NUM_GTE`, `NUM_LT`, `NUM_LTE`
- `DATE_AFTER`, `DATE_BEFORE`

Constraint fields:
- `inverted`: negate result
- `case_insensitive`: lower-case comparisons for string operators

Unknown operators return `false`.

## Error Handling
- Missing `url`/`token`: `ArgumentError`.
- Initial fetch failure: throw to caller (`start`/`create`).
- Polling failures: swallowed to preserve last known good cache.
- Non-200 responses and invalid JSON include diagnostic context where possible.

## Testing Strategy
- Use `testdata/flags.json` fixture to match JS/Python behavioral coverage.
- Cover:
  - basic toggles
  - default strategy
  - user targeting (comma/newline)
  - gradual rollout (0/100/session stickiness)
  - remote address (`ips` and `IPs`)
  - all constraint operators used by current fixture suite
  - multi-strategy OR behavior
  - constrained rollout
  - constructor validation
  - `allFlags` snapshot
- Add a small fetch/start lifecycle test with a local HTTP server stub.

## Packaging and CI
- Add `dart/pubspec.yaml` metadata and dependencies (`http` package).
- Add package README and example usage.
- Add `dart` CI workflow for pull requests and pushes touching `dart/**` or `testdata/**`.
- Add tag-triggered publish workflow (e.g. tags matching `dart/v*`) using `dart pub publish --force` with repository secret token.
- Update repo root README SDK table and quick-start snippets.

## Risks and Mitigations
- Date parsing semantics can differ subtly across languages.
  - Mitigation: keep fixture-driven tests aligned with existing suite assumptions.
- Hash bucketing mismatch would break rollout parity.
  - Mitigation: implement FNV-1a explicitly and test deterministic outputs.
- Polling resource leaks in Flutter hot-reload/dev cycles.
  - Mitigation: make `close()` idempotent and clearly documented.

## Rollout Plan
1. Add Dart package and parity tests.
2. Run tests locally.
3. Add CI and publish workflow.
4. Update root docs.
5. Open PR with behavior parity summary and release tagging instructions.
