# Bandeira Elixir SDK

Official Elixir client SDK for [Bandeira](https://github.com/felipekafuri/bandeira), a self-hosted feature flag service.

## Install

Add to `mix.exs`:

```elixir
def deps do
  [
    {:bandeira, "~> 0.1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Usage

```elixir
alias Bandeira.{Client, Config, Context}

{:ok, client} =
  Client.start_link(%Config{
    url: "http://localhost:8080",
    token: "your-client-token"
  })

if Client.is_enabled(client, "my-flag", %Context{user_id: "user-123"}) do
  # feature is on
end

Client.close(client)
```

## Notes

- The client polls `/api/v1/flags` in the background and caches flags in memory.
- `is_enabled/3` is a pure in-memory lookup and does not do network I/O.
- Initial startup fails fast if the first fetch fails.
- Call `close/1` when running unmanaged clients.
