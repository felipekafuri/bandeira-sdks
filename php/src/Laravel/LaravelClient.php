<?php

declare(strict_types=1);

namespace Bandeira\Laravel;

use Bandeira\Client;
use Bandeira\Context;
use Bandeira\Laravel\Contracts\ContextResolver;

final class LaravelClient
{
    public function __construct(
        private readonly Client $client,
        private readonly ContextResolver $contextResolver,
    ) {
    }

    public function isEnabled(string $name, ?Context $ctx = null): bool
    {
        return $this->client->isEnabled($name, $ctx);
    }

    public function isEnabledForCurrentRequest(string $name): bool
    {
        return $this->client->isEnabled($name, $this->contextResolver->resolve());
    }

    /** @return array<string, bool> */
    public function allFlags(): array
    {
        return $this->client->allFlags();
    }

    public function refresh(): void
    {
        $this->client->refresh();
    }

    public function core(): Client
    {
        return $this->client;
    }
}
