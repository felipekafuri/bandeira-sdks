# Elixir SDK Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an official OTP-first Elixir SDK for Bandeira with strict behavior parity to existing SDKs, including tests, CI, docs, and Hex publish automation.

**Architecture:** Implement `Bandeira.Client` as a `GenServer` that performs fail-fast initial fetch, stores flags in-memory, polls periodically, and evaluates `is_enabled` locally. Keep evaluation logic in a dedicated module and parse API payloads into normalized structs for predictable behavior.

**Tech Stack:** Elixir/Mix, OTP `GenServer`, `Req` for HTTP, ExUnit, GitHub Actions.

---

### Task 1: Scaffold Mix project and package metadata

**Files:**
- Create: `elixir/.formatter.exs`
- Create: `elixir/.gitignore`
- Create: `elixir/mix.exs`
- Create: `elixir/lib/bandeira.ex`
- Create: `elixir/lib/bandeira/config.ex`
- Create: `elixir/lib/bandeira/context.ex`
- Create: `elixir/README.md`

**Step 1: Write the failing test**

```elixir
defmodule BandeiraCompileSmokeTest do
  use ExUnit.Case

  test "public modules compile" do
    assert Code.ensure_loaded?(Bandeira.Client)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd elixir && mix test`
Expected: FAIL because project/modules do not exist.

**Step 3: Write minimal implementation**

- Add Mix project metadata (`name`, `version`, package links, deps).
- Add module exports and config/context structs.

**Step 4: Run test to verify it passes**

Run: `cd elixir && mix format && mix test`
Expected: PASS.

**Step 5: Commit**

```bash
git add elixir/.formatter.exs elixir/.gitignore elixir/mix.exs elixir/lib/bandeira.ex elixir/lib/bandeira/config.ex elixir/lib/bandeira/context.ex elixir/README.md
git commit -m "feat(elixir): scaffold mix package and public types"
```

### Task 2: Implement models and evaluator

**Files:**
- Create: `elixir/lib/bandeira/flag_models.ex`
- Create: `elixir/lib/bandeira/evaluator.ex`
- Test: `elixir/test/bandeira/evaluator_test.exs`

**Step 1: Write the failing test**

```elixir
test "userWithId handles newline-separated ids" do
  client = start_fixture_client()
  assert Bandeira.Client.is_enabled(client, "user-targeting-newlines", %Bandeira.Context{user_id: "user-42"})
end
```

**Step 2: Run test to verify it fails**

Run: `cd elixir && mix test test/bandeira/evaluator_test.exs`
Expected: FAIL due to missing evaluator/model behavior.

**Step 3: Write minimal implementation**

- Parse payload into typed structs.
- Implement strategy and constraint evaluation parity:
  - `default`, `userWithId`, `gradualRollout`, `remoteAddress`
  - operators + `inverted` + `case_insensitive`
  - FNV-1a hash mod 100.

**Step 4: Run test to verify it passes**

Run: `cd elixir && mix test test/bandeira/evaluator_test.exs`
Expected: PASS.

**Step 5: Commit**

```bash
git add elixir/lib/bandeira/flag_models.ex elixir/lib/bandeira/evaluator.ex elixir/test/bandeira/evaluator_test.exs
git commit -m "feat(elixir): add flag models and evaluator parity logic"
```

### Task 3: Implement HTTP repository and GenServer client lifecycle

**Files:**
- Create: `elixir/lib/bandeira/http_flags_repository.ex`
- Create: `elixir/lib/bandeira/client.ex`
- Modify: `elixir/lib/bandeira.ex`
- Test: `elixir/test/bandeira/client_test.exs`

**Step 1: Write the failing test**

```elixir
test "start_link fails fast on unauthorized initial fetch" do
  assert {:error, _} = Bandeira.Client.start_link(%Bandeira.Config{url: server_url(), token: "bad"})
end
```

**Step 2: Run test to verify it fails**

Run: `cd elixir && mix test test/bandeira/client_test.exs`
Expected: FAIL due to missing client/repository.

**Step 3: Write minimal implementation**

- Repository fetches `/api/v1/flags` with bearer auth and decodes JSON.
- `Bandeira.Client`:
  - `start_link/1` fail-fast initial fetch
  - periodic polling
  - `is_enabled/3`, `all_flags/1`, `load_flags/2`, `close/1`
  - keep last-known-good cache on poll errors.

**Step 4: Run test to verify it passes**

Run: `cd elixir && mix test test/bandeira/client_test.exs`
Expected: PASS.

**Step 5: Commit**

```bash
git add elixir/lib/bandeira/http_flags_repository.ex elixir/lib/bandeira/client.ex elixir/lib/bandeira.ex elixir/test/bandeira/client_test.exs
git commit -m "feat(elixir): add polling client and HTTP repository"
```

### Task 4: Add comprehensive parity tests using shared fixtures

**Files:**
- Create: `elixir/test/support/fixtures.ex`
- Modify: `elixir/test/bandeira/evaluator_test.exs`
- Modify: `elixir/test/test_helper.exs`

**Step 1: Write the failing test**

```elixir
test "constraint DATE_AFTER parity" do
  client = start_fixture_client()
  assert Bandeira.Client.is_enabled(client, "constraint-date-after", %Bandeira.Context{properties: %{"signupDate" => "2026-06-15T00:00:00Z"}})
end
```

**Step 2: Run test to verify it fails**

Run: `cd elixir && mix test`
Expected: FAIL for unimplemented or mismatched parity cases.

**Step 3: Write minimal implementation**

- Cover all fixture scenarios mirrored by JS/Python/Dart tests:
  - toggles, strategies, constraints, multi-strategy, constrained rollout, all_flags.

**Step 4: Run test to verify it passes**

Run: `cd elixir && mix test`
Expected: PASS.

**Step 5: Commit**

```bash
git add elixir/test/support/fixtures.ex elixir/test/bandeira/evaluator_test.exs elixir/test/test_helper.exs
git commit -m "test(elixir): add fixture-driven parity coverage"
```

### Task 5: Add GitHub Actions workflow for test and Hex publish

**Files:**
- Create: `.github/workflows/elixir.yml`

**Step 1: Write the failing test**

- N/A (workflow change).

**Step 2: Validate workflow config**

Run: `rg "name: Elixir SDK" .github/workflows/elixir.yml`
Expected: File exists with expected triggers and jobs.

**Step 3: Write minimal implementation**

- Test job for `elixir/**` and `testdata/**`.
- Publish job gated on `refs/tags/elixir/v*` and using `HEX_API_KEY`.

**Step 4: Verify**

Run: `sed -n '1,260p' .github/workflows/elixir.yml`
Expected: Correct triggers, test steps, publish gating.

**Step 5: Commit**

```bash
git add .github/workflows/elixir.yml
git commit -m "ci(elixir): add test and hex publish workflow"
```

### Task 6: Update documentation and root SDK index

**Files:**
- Modify: `README.md`
- Modify: `elixir/README.md`

**Step 1: Write the failing test**

- N/A (docs change).

**Step 2: Validate missing references**

Run: `rg "Elixir" README.md elixir/README.md`
Expected: Initially missing or incomplete.

**Step 3: Write minimal implementation**

- Add Elixir row to SDK table.
- Add Elixir quick-start in root README.
- Add package usage details in `elixir/README.md`.

**Step 4: Verify docs**

Run: `sed -n '1,260p' README.md && sed -n '1,260p' elixir/README.md`
Expected: Consistent install + usage instructions.

**Step 5: Commit**

```bash
git add README.md elixir/README.md
git commit -m "docs: add Elixir SDK usage and index"
```

### Task 7: Final validation and PR preparation

**Files:**
- Modify: `docs/plans/2026-02-19-elixir-sdk-design.md`
- Modify: `docs/plans/2026-02-19-elixir-sdk.md`

**Step 1: Run full checks**

Run: `cd elixir && mix format && mix test`
Expected: PASS.

**Step 2: Review diff and summarize**

Run: `git status --short && git diff --stat`
Expected: Only planned files changed.

**Step 3: Commit docs and final touches**

```bash
git add docs/plans/2026-02-19-elixir-sdk-design.md docs/plans/2026-02-19-elixir-sdk.md
git commit -m "docs: add elixir sdk design and implementation plan"
```

**Step 4: Push branch and open PR**

Run:
```bash
git push -u fork <branch-name>
gh pr create --base main --head <branch-name> --title "feat: add official Elixir SDK" --body-file /tmp/pr.md
```
Expected: PR URL returned.
