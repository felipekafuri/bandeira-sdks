# Bandeira PHP SDK

Official PHP client SDK for [Bandeira](https://github.com/felipekafuri/bandeira), a self-hosted feature flag service.

## Install

Add the repository and require the package:

```json
{
    "repositories": [
        {
            "type": "package",
            "package": {
                "name": "bandeira/bandeira",
                "version": "0.1.0",
                "source": {
                    "url": "https://github.com/felipekafuri/bandeira-sdks.git",
                    "type": "git",
                    "reference": "php/v0.1.0"
                },
                "autoload": {
                    "psr-4": {
                        "Bandeira\\": "php/src/"
                    }
                },
                "require": {
                    "php": "^8.1",
                    "php-http/discovery": "^1.20",
                    "psr/http-client": "^1.0",
                    "psr/http-factory": "^1.0",
                    "psr/http-message": "^1.1 || ^2.0",
                    "illuminate/support": "^10.0 || ^11.0"
                }
            }
        }
    ]
}
```

```bash
composer require bandeira/bandeira
```

## Standalone Usage

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

## Laravel Usage

The package auto-discovers its service provider and facade.

```php
if (Bandeira::isEnabledForCurrentRequest('my-flag')) {
    // feature is on for current request context
}
```

Or pass explicit context:

```php
use Bandeira\Context;
use Bandeira\Laravel\Facades\Bandeira;

$enabled = Bandeira::isEnabled('my-flag', new Context(
    userId: 'user-123',
    properties: ['companyId' => 'acme'],
));
```
