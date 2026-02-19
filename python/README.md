# Bandeira Python SDK

Official Python client SDK for [Bandeira](https://github.com/felipekafuri/bandeira), a self-hosted feature flag service.

## Install

```bash
pip install bandeira
```

## Usage

```python
from bandeira import BandeiraClient, Config, Context

client = BandeiraClient(Config(
    url="http://localhost:8080",
    token="your-client-token",
))
client.start()

if client.is_enabled("my-flag", Context(user_id="user-123")):
    # feature is on
    pass

client.close()
```
