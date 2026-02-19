# Bandeira SDKs

Official client SDKs for [Bandeira](https://github.com/felipekafuri/bandeira), a self-hosted feature flag service.

All SDKs fetch flag definitions from the Bandeira server, cache flags locally, and evaluate strategies in-process — so `isEnabled` calls are pure in-memory lookups with zero network latency.

## SDKs

| Language | Package | Install |
|----------|---------|---------|
| **Go** | [`bandeira-sdks/go`](./go) | `go get github.com/felipekafuri/bandeira-sdks/go` |
| **JavaScript/TypeScript** | [`bandeira`](./js) | `npm install bandeira` |
| **Python** | [`bandeira`](./python) | `pip install bandeira` |
| **PHP** | [`bandeira/bandeira`](./php) | `composer require bandeira/bandeira` |
| **Dart/Flutter** | [`bandeira`](./dart) | `dart pub add bandeira` |
| **Elixir** | [`bandeira`](./elixir) | `{:bandeira, "~> 0.1.0"}` |

## Quick Start

### Go

```go
import bandeira "github.com/felipekafuri/bandeira-sdks/go"

client, err := bandeira.New(bandeira.Config{
    URL:   "http://localhost:8080",
    Token: "your-client-token",
})
defer client.Close()

if client.IsEnabled("my-flag", bandeira.Context{UserID: "user-123"}) {
    // feature is on
}
```

### JavaScript / TypeScript

```typescript
import { BandeiraClient } from "bandeira";

const client = new BandeiraClient({
  url: "http://localhost:8080",
  token: "your-client-token",
});

if (client.isEnabled("my-flag", { userId: "user-123" })) {
  // feature is on
}

client.close();
```

### Python

```python
from bandeira import BandeiraClient

client = BandeiraClient(
    url="http://localhost:8080",
    token="your-client-token",
)

if client.is_enabled("my-flag", user_id="user-123"):
    # feature is on

client.close()
```

### PHP

```php
<?php

use Bandeira\Client;
use Bandeira\Config;
use Bandeira\Context;

$client = new Client(new Config(
    url: 'http://localhost:8080',
    token: 'your-client-token',
));

if ($client->isEnabled('my-flag', new Context(userId: 'user-123'))) {
    // feature is on
}
```

### Laravel

```php
use Bandeira\Laravel\Facades\Bandeira;

if (Bandeira::isEnabledForCurrentRequest('my-flag')) {
    // feature is on for current user/request
}
```

### Dart / Flutter

```dart
import 'package:bandeira/bandeira.dart';

Future<void> main() async {
  final client = await BandeiraClient.create(
    const BandeiraConfig(
      url: "http://localhost:8080",
      token: "your-client-token",
    ),
  );

  if (client.isEnabled("my-flag", const BandeiraContext(userId: "user-123"))) {
    // feature is on
  }

  client.close();
}
```

### Elixir

```elixir
{:ok, client} = Bandeira.Client.start_link(
  url: "http://localhost:8080",
  token: "your-client-token"
)

if Bandeira.Client.enabled?(client, "my-flag", %Bandeira.Context{user_id: "user-123"}) do
  # feature is on
end
```

## License

MIT
