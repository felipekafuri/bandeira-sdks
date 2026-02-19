<?php

declare(strict_types=1);

namespace Bandeira\Tests\Laravel;

use Bandeira\Laravel\BandeiraServiceProvider;
use Bandeira\Tests\TestHelpers\QueueHttpClient;
use Nyholm\Psr7\Factory\Psr17Factory;
use Orchestra\Testbench\TestCase as Orchestra;
use Psr\Http\Client\ClientInterface as PsrHttpClient;
use Psr\Http\Message\RequestFactoryInterface;

abstract class TestCase extends Orchestra
{
    protected QueueHttpClient $httpClient;

    /** @return list<class-string> */
    protected function getPackageProviders($app): array
    {
        return [
            BandeiraServiceProvider::class,
        ];
    }

    protected function getEnvironmentSetUp($app): void
    {
        $app['config']->set('bandeira.url', 'http://localhost:8080');
        $app['config']->set('bandeira.token', 'test-token');
        $app['config']->set('bandeira.poll_interval', 15);
    }

    protected function setUp(): void
    {
        parent::setUp();

        $this->httpClient = new QueueHttpClient();
        $this->app->instance(PsrHttpClient::class, $this->httpClient);
        $this->app->instance(RequestFactoryInterface::class, new Psr17Factory());
    }
}
