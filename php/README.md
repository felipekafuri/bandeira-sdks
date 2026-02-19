# Bandeira PHP SDK

Official PHP client SDK for [Bandeira](https://github.com/felipekafuri/bandeira), a self-hosted feature flag service.

## Install

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
