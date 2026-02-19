<?php

declare(strict_types=1);

namespace Bandeira;

use Psr\Http\Client\ClientInterface;
use Psr\Http\Message\RequestFactoryInterface;

final class Config
{
    public function __construct(
        public string $url,
        public string $token,
        public int $pollInterval = 15,
        public ?ClientInterface $httpClient = null,
        public ?RequestFactoryInterface $requestFactory = null,
    ) {
    }
}
