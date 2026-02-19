<?php

declare(strict_types=1);

namespace Bandeira\Tests;

use Bandeira\Client;
use Bandeira\Config;
use Bandeira\Tests\TestHelpers\QueueHttpClient;
use Nyholm\Psr7\Factory\Psr17Factory;
use Nyholm\Psr7\Response;
use PHPUnit\Framework\TestCase;
use RuntimeException;

final class ClientRefreshTest extends TestCase
{
    public function testStaleRefreshSuccessUpdatesCache(): void
    {
        $httpClient = new QueueHttpClient([
            self::jsonResponse([
                'flags' => [
                    ['name' => 'dynamic-flag', 'enabled' => true, 'strategies' => []],
                ],
            ]),
        ]);

        $client = new Client(new Config(
            url: 'http://localhost:8080',
            token: 'test-token',
            pollInterval: 15,
            httpClient: $httpClient,
            requestFactory: new Psr17Factory(),
        ));

        $client->loadFlags([
            'flags' => [
                ['name' => 'dynamic-flag', 'enabled' => false, 'strategies' => []],
            ],
        ]);

        self::forceCacheStale($client);
        self::assertTrue($client->isEnabled('dynamic-flag'));

        self::assertCount(1, $httpClient->requests);
        self::assertSame('Bearer test-token', $httpClient->requests[0]->getHeaderLine('Authorization'));
        self::assertSame('/api/v1/flags', $httpClient->requests[0]->getUri()->getPath());
    }

    public function testStaleRefreshFailureKeepsLastKnownCache(): void
    {
        $httpClient = new QueueHttpClient([new RuntimeException('network down')]);

        $client = new Client(new Config(
            url: 'http://localhost:8080',
            token: 'test-token',
            pollInterval: 15,
            httpClient: $httpClient,
            requestFactory: new Psr17Factory(),
        ));

        $client->loadFlags([
            'flags' => [
                ['name' => 'cached-flag', 'enabled' => true, 'strategies' => []],
            ],
        ]);

        self::forceCacheStale($client);
        self::assertTrue($client->isEnabled('cached-flag'));
    }

    private static function jsonResponse(array $payload): Response
    {
        return new Response(
            200,
            ['Content-Type' => 'application/json'],
            json_encode($payload, JSON_THROW_ON_ERROR),
        );
    }

    private static function forceCacheStale(Client $client): void
    {
        $ref = new \ReflectionClass($client);
        $prop = $ref->getProperty('lastFetchAtEpoch');
        $prop->setAccessible(true);
        $prop->setValue($client, time() - 3600);
    }
}
