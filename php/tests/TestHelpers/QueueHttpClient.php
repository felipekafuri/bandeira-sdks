<?php

declare(strict_types=1);

namespace Bandeira\Tests\TestHelpers;

use Psr\Http\Client\ClientInterface;
use Psr\Http\Message\RequestInterface;
use Psr\Http\Message\ResponseInterface;
use RuntimeException;
use Throwable;

final class QueueHttpClient implements ClientInterface
{
    /** @var list<ResponseInterface|Throwable> */
    private array $queue;

    /** @var list<RequestInterface> */
    public array $requests = [];

    /** @param list<ResponseInterface|Throwable> $queue */
    public function __construct(array $queue = [])
    {
        $this->queue = $queue;
    }

    public function sendRequest(RequestInterface $request): ResponseInterface
    {
        $this->requests[] = $request;

        if ($this->queue === []) {
            throw new RuntimeException('no queued HTTP response');
        }

        $next = array_shift($this->queue);
        if ($next instanceof Throwable) {
            throw $next;
        }

        return $next;
    }
}
