# Elixir SDK Design

## Context
This repository already ships official Bandeira SDKs for Go, JavaScript/TypeScript, Python, and Dart. All SDKs share the same operating model: poll `/api/v1/flags`, cache flags in memory, and evaluate strategies locally so runtime checks never do network I/O.

Goal: add an official Elixir SDK with strict behavior parity (no extra features) and release automation consistent with existing SDK workflows.

## Objectives
- Build an OTP-first Elixir client using a supervised `GenServer`.
- Keep strategy/constraint semantics aligned with existing SDKs and shared fixtures in `testdata/flags.json`.
- Provide Hex publishing automation on version tags.
- Keep public API minimal and parity-focused.

## Non-Goals
- Adding telemetry, metrics hooks, fallback value APIs, or additional product behavior.
- Deviating from shared fixture semantics.
- Building multiple packaging variants in this PR.

## Architecture
Package path: `elixir/`

Public API:
- `Bandeira.Config`
- `Bandeira.Context`
- `Bandeira.Client`

`Bandeira.Client` is an OTP `GenServer` exposing:
- `start_link/1`
- `is_enabled/3`
- `all_flags/1`
- `close/1`
- `load_flags/2` (test-parity helper)

Internal modules:
- `Bandeira.FlagModels` for normalized decoded payload structs.
- `Bandeira.HTTPFlagsRepository` for HTTP fetch and decode from `/api/v1/flags`.
- `Bandeira.Evaluator` for strategy + constraint evaluation.

State model:
- `%{config: ..., flags_by_name: %{}, timer_ref: ...}`
- Initial fetch in `start_link/1` fails fast.
- Periodic polling replaces cache atomically.

## Data Flow and Lifecycle
1. `start_link/1` validates required `url` and `token`.
2. Initial fetch loads flags before the process is considered ready.
3. Polling is scheduled with `Process.send_after/3` using configured interval (default 15s).
4. Poll success updates `flags_by_name`; poll failure keeps last known good cache.
5. `is_enabled/3` reads in-memory cache only and applies evaluation rules.
6. `all_flags/1` returns `%{flag_name => enabled_boolean}` snapshot.
7. `close/1` stops the client process cleanly.

## Evaluation Rules (Parity)
### Flag behavior
- Missing flag: `false`
- Disabled flag: `false`
- Enabled flag without strategies: `true`
- Enabled flag with strategies: OR across strategies

### Strategy behavior
- `default`: `true`
- `userWithId`:
  - Read `parameters.userIds` as string
  - Split on commas/newlines
  - Match against `context.user_id`
- `gradualRollout`:
  - Parse `parameters.rollout` from number/string
  - `>=100 => true`, `<=0 => false`
  - `stickiness` from `userId`, `sessionId`, or custom property key
  - Optional `groupId`
  - Deterministic bucket via FNV-1a 32-bit hash mod 100
- `remoteAddress`:
  - Accept both `ips` and legacy `IPs`
  - Exact address match or prefix match for entries ending with `.`
- Unknown strategy: `true` (fail-open parity)

### Constraint behavior
- AND across constraints in a strategy.
- Operators:
  - `IN`, `NOT_IN`
  - `STR_CONTAINS`, `STR_STARTS_WITH`, `STR_ENDS_WITH`
  - `NUM_EQ`, `NUM_GT`, `NUM_GTE`, `NUM_LT`, `NUM_LTE`
  - `DATE_AFTER`, `DATE_BEFORE`
- `inverted`: negates result.
- `case_insensitive`: lowercase compare for string operators.
- Unknown operator: `false`.

## Error Handling
- Missing URL/token: argument validation error.
- Initial fetch failure: return startup error (fail fast).
- Polling failure: swallow error and keep cache.
- Non-200 responses include status/body in message.
- Invalid JSON returns decode failure error.

## Testing Strategy
- Reuse shared fixture file `testdata/flags.json` for parity assertions.
- ExUnit coverage for:
  - basic toggles
  - default strategy
  - user targeting (comma/newline)
  - gradual rollout (0/100/stickiness)
  - remote address (`ips` and `IPs`)
  - constraint operators used by fixtures
  - multi-strategy OR
  - constrained rollout
  - validation and `all_flags`
- Add local HTTP server tests for startup fetch and auth header behavior.

## CI and Publishing
- Add `.github/workflows/elixir.yml`:
  - Test on pushes/PRs affecting `elixir/**` and `testdata/**`
  - Publish on tags `elixir/v*`
- Publish job uses `HEX_API_KEY` repository secret with `mix hex.publish --yes`.

## Documentation
- Add `elixir/README.md` with install and supervision usage.
- Update root `README.md` SDK table and quick-start section with Elixir sample.

## Risks and Mitigations
- Hash or operator mismatch could break parity.
  - Mitigation: fixture-driven tests matching other SDKs.
- Polling lifecycle bugs in long-running processes.
  - Mitigation: OTP `GenServer`, idempotent close behavior, focused lifecycle tests.

## Rollout Plan
1. Scaffold Elixir Mix project + modules.
2. Implement evaluator/repository/client with parity logic.
3. Add fixture-based tests and lifecycle tests.
4. Add CI + publish workflow.
5. Update docs and open PR with parity summary.
