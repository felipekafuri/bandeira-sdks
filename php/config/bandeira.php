<?php

declare(strict_types=1);

use Bandeira\Laravel\DefaultContextResolver;

return [
    'url' => env('BANDEIRA_URL', 'http://localhost:8080'),
    'token' => env('BANDEIRA_TOKEN', ''),
    'poll_interval' => (int) env('BANDEIRA_POLL_INTERVAL', 15),
    'context_resolver' => DefaultContextResolver::class,
    'context_properties' => [],
];
