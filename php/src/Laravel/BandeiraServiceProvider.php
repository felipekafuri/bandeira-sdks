<?php

declare(strict_types=1);

namespace Bandeira\Laravel;

use Bandeira\Client;
use Bandeira\Config;
use Bandeira\Laravel\Contracts\ContextResolver;
use Illuminate\Contracts\Container\Container;
use Illuminate\Support\ServiceProvider;
use Psr\Http\Client\ClientInterface as PsrHttpClient;
use Psr\Http\Message\RequestFactoryInterface;

final class BandeiraServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->mergeConfigFrom($this->configPath(), 'bandeira');

        $this->app->singleton(Config::class, function (Container $app): Config {
            /** @var array<string, mixed> $cfg */
            $cfg = $app->make('config')->get('bandeira', []);

            $httpClient = $app->bound(PsrHttpClient::class)
                ? $app->make(PsrHttpClient::class)
                : null;
            $requestFactory = $app->bound(RequestFactoryInterface::class)
                ? $app->make(RequestFactoryInterface::class)
                : null;

            return new Config(
                url: is_string($cfg['url'] ?? null) ? $cfg['url'] : '',
                token: is_string($cfg['token'] ?? null) ? $cfg['token'] : '',
                pollInterval: is_numeric($cfg['poll_interval'] ?? null) ? (int) $cfg['poll_interval'] : 15,
                httpClient: $httpClient,
                requestFactory: $requestFactory,
            );
        });

        $this->app->singleton(Client::class, static fn (Container $app): Client => new Client($app->make(Config::class)));

        $this->app->bind(ContextResolver::class, static function (Container $app): ContextResolver {
            $resolverClass = $app->make('config')->get('bandeira.context_resolver', DefaultContextResolver::class);
            if (!is_string($resolverClass) || $resolverClass === '') {
                $resolverClass = DefaultContextResolver::class;
            }

            /** @var ContextResolver $resolver */
            $resolver = $app->make($resolverClass);

            return $resolver;
        });

        $this->app->singleton(
            LaravelClient::class,
            static fn (Container $app): LaravelClient => new LaravelClient(
                $app->make(Client::class),
                $app->make(ContextResolver::class),
            ),
        );
        $this->app->alias(LaravelClient::class, 'bandeira');
    }

    public function boot(): void
    {
        if ($this->app->runningInConsole()) {
            $this->publishes([
                $this->configPath() => config_path('bandeira.php'),
            ], 'bandeira-config');
        }
    }

    private function configPath(): string
    {
        return dirname(__DIR__, 2) . '/config/bandeira.php';
    }
}
