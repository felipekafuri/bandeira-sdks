<?php

declare(strict_types=1);

namespace Bandeira\Tests\Laravel;

use Bandeira\Client;
use Bandeira\Config;
use Bandeira\Laravel\Contracts\ContextResolver;
use Bandeira\Laravel\Facades\Bandeira as BandeiraFacade;
use Bandeira\Laravel\LaravelClient;
use Nyholm\Psr7\Response;

final class LaravelIntegrationTest extends TestCase
{
    public function testServiceProviderRegistersCoreClientSingleton(): void
    {
        $client = $this->app->make(Client::class);
        self::assertInstanceOf(Client::class, $client);
    }

    public function testFacadeProxiesToLaravelClient(): void
    {
        $this->httpClient = new \Bandeira\Tests\TestHelpers\QueueHttpClient([
            new Response(200, ['Content-Type' => 'application/json'], json_encode([
                'flags' => [
                    ['name' => 'my-flag', 'enabled' => true, 'strategies' => []],
                ],
            ], JSON_THROW_ON_ERROR)),
        ]);

        $this->app->instance(\Psr\Http\Client\ClientInterface::class, $this->httpClient);
        $this->app->forgetInstance(Client::class);
        $this->app->forgetInstance(LaravelClient::class);

        self::assertTrue(BandeiraFacade::isEnabledForCurrentRequest('my-flag'));
    }

    public function testDefaultContextResolverUsesAuthRequestAndProperties(): void
    {
        $this->app['config']->set('bandeira.context_properties', [
            'companyId' => static fn (): string => 'acme',
        ]);

        $this->app->instance('request', \Illuminate\Http\Request::create(
            '/foo',
            'GET',
            [],
            [],
            [],
            ['REMOTE_ADDR' => '10.0.0.1'],
        ));

        $this->app->instance('auth', new class {
            public function user(): object
            {
                return new class {
                    public function getAuthIdentifier(): string
                    {
                        return 'user-42';
                    }
                };
            }
        });

        $resolver = $this->app->make(ContextResolver::class);
        $ctx = $resolver->resolve();

        self::assertSame('user-42', $ctx->userId);
        self::assertSame('10.0.0.1', $ctx->remoteAddress);
        self::assertSame('acme', $ctx->properties['companyId']);
    }

    public function testConfigWiring(): void
    {
        $this->app['config']->set('bandeira.url', 'https://flags.internal');
        $this->app['config']->set('bandeira.token', 'abc123');
        $this->app['config']->set('bandeira.poll_interval', 42);
        $this->app->forgetInstance(Config::class);

        $config = $this->app->make(Config::class);

        self::assertSame('https://flags.internal', $config->url);
        self::assertSame('abc123', $config->token);
        self::assertSame(42, $config->pollInterval);
    }
}
