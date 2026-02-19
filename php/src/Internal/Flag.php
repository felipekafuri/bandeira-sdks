<?php

declare(strict_types=1);

namespace Bandeira\Internal;

final class Flag
{
    /**
     * @param list<Strategy> $strategies
     */
    public function __construct(
        public readonly string $name,
        public readonly bool $enabled,
        public readonly array $strategies,
    ) {
    }

    /**
     * @param array<string, mixed> $data
     */
    public static function fromArray(array $data): ?self
    {
        if (!is_string($data['name'] ?? null) || $data['name'] === '') {
            return null;
        }

        $strategies = [];
        $rawStrategies = $data['strategies'] ?? [];
        if (is_array($rawStrategies)) {
            foreach ($rawStrategies as $strategy) {
                if (is_array($strategy)) {
                    $strategies[] = Strategy::fromArray($strategy);
                }
            }
        }

        return new self(
            name: $data['name'],
            enabled: (bool) ($data['enabled'] ?? false),
            strategies: $strategies,
        );
    }
}
