# Dart/Flutter SDK Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build and ship an official Dart/Flutter-compatible Bandeira SDK with behavior parity to the Go, JS/TS, and Python SDKs, including tests, CI, and tag-based publish workflow.

**Architecture:** Add a pure Dart package at `dart/` with a small public API (`BandeiraConfig`, `BandeiraContext`, `BandeiraClient`) and internal modules for models, HTTP fetch, and strategy/constraint evaluation. Cache flags in-memory and poll in the background; evaluate `isEnabled` from cache only.

**Tech Stack:** Dart 3 (`http`, `test`, `lints`), GitHub Actions.

---

### Task 1: Scaffold Dart package metadata and entrypoint

**Files:**
- Create: `dart/pubspec.yaml`
- Create: `dart/README.md`
- Create: `dart/analysis_options.yaml`
- Create: `dart/lib/bandeira.dart`

**Step 1: Write the failing test**

```dart
import 'package:bandeira/bandeira.dart';

void main() {
  final cfg = BandeiraConfig(url: 'http://localhost', token: 't');
  final client = BandeiraClient(cfg);
  client.close();
}
```

**Step 2: Run test to verify it fails**

Run: `cd dart && dart analyze`
Expected: FAIL with unresolved package/library symbols.

**Step 3: Write minimal implementation**

```dart
library bandeira;

export 'src/client.dart';
export 'src/models.dart';
```

Also add package metadata and dependencies in `pubspec.yaml`.

**Step 4: Run test to verify it passes**

Run: `cd dart && dart pub get && dart analyze`
Expected: PASS with no unresolved package errors.

**Step 5: Commit**

```bash
git add dart/pubspec.yaml dart/README.md dart/analysis_options.yaml dart/lib/bandeira.dart
git commit -m "feat(dart): scaffold package metadata and exports"
```

### Task 2: Implement public models and API response parsing

**Files:**
- Create: `dart/lib/src/models.dart`
- Test: `dart/test/models_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:test/test.dart';
import 'package:bandeira/bandeira.dart';

void main() {
  test('parses API flags payload', () {
    final response = ApiResponse.fromJson({'flags': []});
    expect(response.flags, isEmpty);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `cd dart && dart test test/models_test.dart`
Expected: FAIL with missing `ApiResponse` model.

**Step 3: Write minimal implementation**

```dart
class BandeiraConfig { ... }
class BandeiraContext { ... }
class ApiResponse { ... }
class Flag { ... }
class Strategy { ... }
class Constraint { ... }
```

Include safe defaults for missing JSON fields and helpers for dynamic parameter access.

**Step 4: Run test to verify it passes**

Run: `cd dart && dart test test/models_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add dart/lib/src/models.dart dart/test/models_test.dart
git commit -m "feat(dart): add config/context and flag response models"
```

### Task 3: Implement evaluator helpers (split + hash + operator core)

**Files:**
- Create: `dart/lib/src/evaluator.dart`
- Test: `dart/test/evaluator_helpers_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:test/test.dart';
import 'package:bandeira/src/evaluator.dart';

void main() {
  test('splitMulti handles newlines and commas', () {
    expect(splitMulti('a,b\nc'), ['a', 'b', 'c']);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `cd dart && dart test test/evaluator_helpers_test.dart`
Expected: FAIL with missing helpers.

**Step 3: Write minimal implementation**

```dart
List<String> splitMulti(String s) { ... }
int normalizedHash(String value) { ... } // FNV-1a 32-bit, mod 100
```

**Step 4: Run test to verify it passes**

Run: `cd dart && dart test test/evaluator_helpers_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add dart/lib/src/evaluator.dart dart/test/evaluator_helpers_test.dart
git commit -m "feat(dart): add evaluator helpers for split and hashing"
```

### Task 4: Implement full strategy and constraint evaluation

**Files:**
- Modify: `dart/lib/src/evaluator.dart`
- Test: `dart/test/evaluator_logic_test.dart`

**Step 1: Write the failing test**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:bandeira/bandeira.dart';

void main() {
  late ApiResponse fixtures;

  setUpAll(() {
    final raw = File('../testdata/flags.json').readAsStringSync();
    fixtures = ApiResponse.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  });

  test('userWithId newline targeting', () {
    final flag = fixtures.flags.firstWhere((f) => f.name == 'user-targeting-newlines');
    final enabled = evaluateFlag(flag, const BandeiraContext(userId: 'user-42'));
    expect(enabled, isTrue);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `cd dart && dart test test/evaluator_logic_test.dart`
Expected: FAIL due to incomplete strategy/constraint evaluator.

**Step 3: Write minimal implementation**

```dart
bool evaluateFlag(Flag flag, BandeiraContext ctx) { ... }
bool evaluateStrategy(Strategy strategy, BandeiraContext ctx) { ... }
bool evaluateConstraint(Constraint constraint, BandeiraContext ctx) { ... }
```

Implement all parity behavior:
- Strategies: `default`, `userWithId`, `gradualRollout`, `remoteAddress`, unknown strategy fail-open.
- Constraints/operators: `IN`, `NOT_IN`, string ops, numeric ops, date ops, inverted/case-insensitive.

**Step 4: Run test to verify it passes**

Run: `cd dart && dart test test/evaluator_logic_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add dart/lib/src/evaluator.dart dart/test/evaluator_logic_test.dart
git commit -m "feat(dart): implement strategy and constraint evaluator"
```

### Task 5: Implement HTTP repository and error shaping

**Files:**
- Create: `dart/lib/src/http_flags_repository.dart`
- Test: `dart/test/http_flags_repository_test.dart`

**Step 1: Write the failing test**

```dart
test('throws on non-200 response', () async {
  final repo = HttpFlagsRepository(...);
  expect(repo.fetchFlags(), throwsA(isA<StateError>()));
});
```

**Step 2: Run test to verify it fails**

Run: `cd dart && dart test test/http_flags_repository_test.dart`
Expected: FAIL due to missing repository.

**Step 3: Write minimal implementation**

```dart
class HttpFlagsRepository {
  Future<Map<String, Flag>> fetchFlags() async { ... }
}
```

Include:
- URL normalization
- Bearer token header
- JSON decode into `ApiResponse`
- status/body in thrown error message

**Step 4: Run test to verify it passes**

Run: `cd dart && dart test test/http_flags_repository_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add dart/lib/src/http_flags_repository.dart dart/test/http_flags_repository_test.dart
git commit -m "feat(dart): add HTTP flags fetch repository"
```

### Task 6: Implement `BandeiraClient` lifecycle, polling, and APIs

**Files:**
- Create: `dart/lib/src/client.dart`
- Test: `dart/test/client_lifecycle_test.dart`

**Step 1: Write the failing test**

```dart
test('create() performs initial fetch and serves flags', () async {
  final client = await BandeiraClient.create(BandeiraConfig(...));
  expect(client.isEnabled('simple-on'), isTrue);
  await client.close();
});
```

**Step 2: Run test to verify it fails**

Run: `cd dart && dart test test/client_lifecycle_test.dart`
Expected: FAIL due to missing client implementation.

**Step 3: Write minimal implementation**

```dart
class BandeiraClient {
  BandeiraClient(BandeiraConfig config, {http.Client? httpClient});
  static Future<BandeiraClient> create(BandeiraConfig config, {http.Client? httpClient});
  Future<void> start();
  bool isEnabled(String name, [BandeiraContext? ctx]);
  Map<String, bool> allFlags();
  void loadFlags(Map<String, dynamic> response);
  Future<void> close();
}
```

Implementation requirements:
- fail-fast on initial fetch
- background polling with `Timer.periodic`
- swallow polling errors
- idempotent `start` and `close`
- cache replacement as atomic map assignment

**Step 4: Run test to verify it passes**

Run: `cd dart && dart test test/client_lifecycle_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add dart/lib/src/client.dart dart/test/client_lifecycle_test.dart
git commit -m "feat(dart): add client lifecycle and polling"
```

### Task 7: Add parity fixture test suite using shared `testdata/flags.json`

**Files:**
- Create: `dart/test/bandeira_test.dart`

**Step 1: Write the failing test**

```dart
test('unknown flag returns false', () {
  final c = createClientFromFixtures();
  expect(c.isEnabled('nonexistent'), isFalse);
});
```

**Step 2: Run test to verify it fails**

Run: `cd dart && dart test test/bandeira_test.dart`
Expected: FAIL until fixture harness and parity cases are complete.

**Step 3: Write minimal implementation**

Add full parity cases equivalent to JS/Python:
- basic toggles
- default strategy
- user targeting + newline format
- rollout 0/100/no stickiness/session
- remoteAddress + legacy `IPs`
- all constraints in fixture
- multi-strategy OR logic
- constrained rollout
- `allFlags`
- input validation (`url`, `token`)

**Step 4: Run test to verify it passes**

Run: `cd dart && dart test test/bandeira_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add dart/test/bandeira_test.dart
git commit -m "test(dart): add fixture parity suite"
```

### Task 8: Improve docs and add usage examples

**Files:**
- Modify: `dart/README.md`
- Modify: `README.md`

**Step 1: Write the failing test**

```text
N/A (docs task)
```

**Step 2: Run test to verify it fails**

Run: `rg "Dart|Flutter" README.md`
Expected: no Dart/Flutter SDK entry present.

**Step 3: Write minimal implementation**

Update docs with:
- root SDK table row for Dart/Flutter
- install command (`dart pub add bandeira`)
- quick start snippets showing both `create()` and `start()` styles
- close semantics and context examples

**Step 4: Run test to verify it passes**

Run: `rg "Dart|Flutter" README.md dart/README.md`
Expected: Dart/Flutter docs present.

**Step 5: Commit**

```bash
git add README.md dart/README.md
git commit -m "docs: add dart/flutter SDK usage docs"
```

### Task 9: Add GitHub Actions workflow for Dart test + publish

**Files:**
- Create: `.github/workflows/dart.yml`

**Step 1: Write the failing test**

```text
N/A (workflow task)
```

**Step 2: Run test to verify it fails**

Run: `test -f .github/workflows/dart.yml || echo missing`
Expected: `missing`.

**Step 3: Write minimal implementation**

Workflow requirements:
- `name: Dart SDK`
- triggers:
  - push/pr when `dart/**` or `testdata/**` changes
  - tag push `dart/v*`
- test job:
  - checkout
  - setup Dart stable
  - `dart pub get`, `dart analyze`, `dart test`
- publish job:
  - needs test
  - only runs for `refs/tags/dart/v*`
  - uses `PUB_CREDENTIALS_JSON` secret to write `$HOME/.pub-cache/credentials.json`
  - `dart pub publish --force`

**Step 4: Run test to verify it passes**

Run: `rg "name: Dart SDK|dart/v\*|dart pub publish" .github/workflows/dart.yml`
Expected: workflow contains required CI/publish markers.

**Step 5: Commit**

```bash
git add .github/workflows/dart.yml
git commit -m "ci: add dart SDK test and publish workflow"
```

### Task 10: Final verification and PR preparation

**Files:**
- Modify: `dart/**` (if fixes needed)
- Modify: `.github/workflows/dart.yml` (if fixes needed)
- Modify: `README.md` (if fixes needed)

**Step 1: Write the failing test**

```text
N/A (integration verification)
```

**Step 2: Run test to verify it fails**

Run: `cd dart && dart analyze && dart test`
Expected: if failures appear, capture and fix.

**Step 3: Write minimal implementation**

Fix lint/test issues and API/doc inconsistencies discovered in full run.

**Step 4: Run test to verify it passes**

Run:
- `cd dart && dart analyze && dart test`
- `git status --short`

Expected:
- all analyzer/tests pass
- clean git state except intended tracked changes

**Step 5: Commit**

```bash
git add dart .github/workflows/dart.yml README.md
git commit -m "feat: add official Dart/Flutter SDK"
```
