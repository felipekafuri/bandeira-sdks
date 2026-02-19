<?php

declare(strict_types=1);

namespace Bandeira\Internal;

final class Strategy
{
    /**
     * @param array<string, mixed> $parameters
     * @param list<Constraint> $constraints
     */
    public function __construct(
        public readonly string $name,
        public readonly array $parameters,
        public readonly array $constraints,
    ) {
    }

    /**
     * @param array<string, mixed> $data
     */
    public static function fromArray(array $data): self
    {
        $parameters = is_array($data['parameters'] ?? null) ? $data['parameters'] : [];

        $constraints = [];
        $rawConstraints = $data['constraints'] ?? [];
        if (is_array($rawConstraints)) {
            foreach ($rawConstraints as $constraint) {
                if (is_array($constraint)) {
                    $constraints[] = Constraint::fromArray($constraint);
                }
            }
        }

        return new self(
            name: is_string($data['name'] ?? null) ? $data['name'] : '',
            parameters: $parameters,
            constraints: $constraints,
        );
    }
}
