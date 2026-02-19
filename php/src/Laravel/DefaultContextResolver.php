<?php

declare(strict_types=1);

namespace Bandeira\Laravel;

use Bandeira\Context;
use Bandeira\Laravel\Contracts\ContextResolver;
use Illuminate\Contracts\Container\Container;
use Illuminate\Http\Request;

final class DefaultContextResolver implements ContextResolver
{
    public function __construct(private readonly Container $container)
    {
    }

    public function resolve(): Context
    {
        $request = $this->container->bound('request') ? $this->container->make('request') : null;
        if (!$request instanceof Request) {
            $request = null;
        }

        $user = null;
        if ($this->container->bound('auth')) {
            $auth = $this->container->make('auth');
            if (is_object($auth) && method_exists($auth, 'user')) {
                $user = $auth->user();
            }
        }

        $userId = '';
        if (is_object($user) && method_exists($user, 'getAuthIdentifier')) {
            $identifier = $user->getAuthIdentifier();
            if (is_scalar($identifier)) {
                $userId = (string) $identifier;
            }
        }

        /** @var mixed $propertyConfig */
        $propertyConfig = $this->container->make('config')->get('bandeira.context_properties', []);
        $properties = [];
        if (is_array($propertyConfig)) {
            foreach ($propertyConfig as $key => $resolver) {
                if (!is_string($key) || $key === '') {
                    continue;
                }

                if (is_callable($resolver)) {
                    $value = $resolver($request, $user, $this->container);
                    if (is_scalar($value) && $value !== '') {
                        $properties[$key] = (string) $value;
                    }
                    continue;
                }

                if (is_scalar($resolver) && $resolver !== '') {
                    $properties[$key] = (string) $resolver;
                }
            }
        }

        return new Context(
            userId: $userId,
            remoteAddress: $request?->ip() ?? '',
            properties: $properties,
        );
    }
}
