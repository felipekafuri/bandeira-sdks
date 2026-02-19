<?php

declare(strict_types=1);

namespace Bandeira;

final class Context
{
    /** @param array<string, string> $properties */
    public function __construct(
        public string $userId = '',
        public string $sessionId = '',
        public string $remoteAddress = '',
        public array $properties = [],
    ) {
    }
}
