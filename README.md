# Bandeira SDKs

Official client SDKs for [Bandeira](https://github.com/felipekafuri/bandeira), a self-hosted feature flag service.

All SDKs poll the Bandeira server, cache flags locally, and evaluate strategies in-process — so `isEnabled` calls are pure in-memory lookups with zero network latency.

## SDKs

| Language | Package | Install |
|----------|---------|---------|
| **Go** | [`bandeira-sdks/go`](./go) | `go get github.com/felipekafuri/bandeira-sdks/go` |
| **JavaScript/TypeScript** | [`bandeira`](./js) | `npm install bandeira` |
| **Python** | [`bandeira`](./python) | `pip install bandeira` |

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

## License

MIT
