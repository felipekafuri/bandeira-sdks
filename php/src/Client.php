<?php

declare(strict_types=1);

namespace Bandeira;

use Bandeira\Exception\BandeiraException;
use Bandeira\Exception\ConfigurationException;
use Bandeira\Exception\ResponseException;
use Bandeira\Exception\TransportException;
use Bandeira\Internal\Evaluator;
use Bandeira\Internal\Flag;
use Bandeira\Internal\Parser;
use Http\Discovery\Psr17FactoryDiscovery;
use Http\Discovery\Psr18ClientDiscovery;
use JsonException;
use Psr\Http\Client\ClientInterface;
use Psr\Http\Message\RequestFactoryInterface;
use Throwable;

final class Client
{
    private Config $config;
    private ?ClientInterface $httpClient;
    private ?RequestFactoryInterface $requestFactory;

    /** @var array<string, Flag> */
    private array $flags = [];

    private ?int $lastFetchAtEpoch = null;

    public function __construct(Config $config)
    {
        if (trim($config->url) === '') {
            throw new ConfigurationException('bandeira: url is required');
        }

        if (trim($config->token) === '') {
            throw new ConfigurationException('bandeira: token is required');
        }

        $pollInterval = $config->pollInterval > 0 ? $config->pollInterval : 15;

        $this->config = new Config(
            url: rtrim($config->url, '/'),
            token: $config->token,
            pollInterval: $pollInterval,
            httpClient: $config->httpClient,
            requestFactory: $config->requestFactory,
        );

        $this->httpClient = $config->httpClient;
        $this->requestFactory = $config->requestFactory;
    }

    public function refresh(): void
    {
        $requestFactory = $this->requestFactory ??= $this->discoverRequestFactory();
        $request = $requestFactory
            ->createRequest('GET', $this->config->url . '/api/v1/flags')
            ->withHeader('Authorization', 'Bearer ' . $this->config->token);

        $httpClient = $this->httpClient ??= $this->discoverHttpClient();
        try {
            $response = $httpClient->sendRequest($request);
        } catch (Throwable $e) {
            throw new TransportException('bandeira: request failed: ' . $e->getMessage(), 0, $e);
        }

        $body = (string) $response->getBody();
        if ($response->getStatusCode() !== 200) {
            throw new ResponseException(sprintf('bandeira: unexpected status %d: %s', $response->getStatusCode(), $body));
        }

        try {
            /** @var mixed $decoded */
            $decoded = json_decode($body, true, 512, JSON_THROW_ON_ERROR);
        } catch (JsonException $e) {
            throw new ResponseException('bandeira: failed to decode response: ' . $e->getMessage(), 0, $e);
        }

        if (!is_array($decoded)) {
            throw new ResponseException('bandeira: invalid JSON response');
        }

        $this->flags = Parser::parseFlags($decoded);
        $this->lastFetchAtEpoch = time();
    }

    /**
     * Load an API response payload directly into the local cache.
     *
     * @param array<string, mixed> $response
     */
    public function loadFlags(array $response): void
    {
        $this->flags = Parser::parseFlags($response);
        $this->lastFetchAtEpoch = time();
    }

    public function isEnabled(string $name, ?Context $ctx = null): bool
    {
        $this->tryRefreshIfStale();

        $flag = $this->flags[$name] ?? null;
        if ($flag === null || !$flag->enabled) {
            return false;
        }

        if ($flag->strategies === []) {
            return true;
        }

        $evalContext = $ctx ?? new Context();
        foreach ($flag->strategies as $strategy) {
            if (Evaluator::evaluateStrategy($strategy, $evalContext)) {
                return true;
            }
        }

        return false;
    }

    /** @return array<string, bool> */
    public function allFlags(): array
    {
        $this->tryRefreshIfStale();

        $result = [];
        foreach ($this->flags as $name => $flag) {
            $result[$name] = $flag->enabled;
        }

        return $result;
    }

    private function tryRefreshIfStale(): void
    {
        if (!$this->isCacheStale()) {
            return;
        }

        try {
            $this->refresh();
        } catch (BandeiraException) {
            // Keep last-known local cache on refresh failure.
        }
    }

    private function isCacheStale(): bool
    {
        if ($this->lastFetchAtEpoch === null) {
            return true;
        }

        return (time() - $this->lastFetchAtEpoch) >= $this->config->pollInterval;
    }

    private function discoverHttpClient(): ClientInterface
    {
        try {
            return Psr18ClientDiscovery::find();
        } catch (Throwable $e) {
            throw new ConfigurationException('bandeira: unable to discover a PSR-18 HTTP client', 0, $e);
        }
    }

    private function discoverRequestFactory(): RequestFactoryInterface
    {
        try {
            return Psr17FactoryDiscovery::findRequestFactory();
        } catch (Throwable $e) {
            throw new ConfigurationException('bandeira: unable to discover a PSR-17 request factory', 0, $e);
        }
    }
}
