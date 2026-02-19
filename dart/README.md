# Bandeira Dart/Flutter SDK

Official Dart client SDK for [Bandeira](https://github.com/felipekafuri/bandeira), a self-hosted feature flag service.

## Install

```bash
dart pub add bandeira
```

For Flutter apps:

```bash
flutter pub add bandeira
```

## Usage

### Option 1: Fail-fast startup with `create()`

```dart
import 'package:bandeira/bandeira.dart';

Future<void> main() async {
  final client = await BandeiraClient.create(
    const BandeiraConfig(
      url: 'http://localhost:8080',
      token: 'your-client-token',
    ),
  );

  final enabled = client.isEnabled(
    'my-flag',
    const BandeiraContext(userId: 'user-123'),
  );

  if (enabled) {
    // feature is on
  }

  client.close();
}
```

### Option 2: Construct then `start()`

```dart
import 'package:bandeira/bandeira.dart';

Future<void> main() async {
  final client = BandeiraClient(
    const BandeiraConfig(
      url: 'http://localhost:8080',
      token: 'your-client-token',
    ),
  );

  await client.start();

  if (client.isEnabled('my-flag')) {
    // feature is on
  }

  client.close();
}
```

## Notes

- The client polls `/api/v1/flags` in the background and caches flags in memory.
- `isEnabled` is an in-memory lookup and does not do network I/O.
- Call `close()` when done to stop polling and release resources.
