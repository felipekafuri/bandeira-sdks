<?php

declare(strict_types=1);

namespace Bandeira\Internal;

final class Constraint
{
    /**
     * @param list<string> $values
     */
    public function __construct(
        public readonly string $contextName,
        public readonly string $operator,
        public readonly array $values,
        public readonly bool $inverted,
        public readonly bool $caseInsensitive,
    ) {
    }

    /**
     * @param array<string, mixed> $data
     */
    public static function fromArray(array $data): self
    {
        $values = [];
        $rawValues = $data['values'] ?? [];
        if (is_array($rawValues)) {
            foreach ($rawValues as $value) {
                if (is_scalar($value)) {
                    $values[] = (string) $value;
                }
            }
        }

        return new self(
            contextName: is_string($data['context_name'] ?? null) ? $data['context_name'] : '',
            operator: is_string($data['operator'] ?? null) ? $data['operator'] : '',
            values: $values,
            inverted: (bool) ($data['inverted'] ?? false),
            caseInsensitive: (bool) ($data['case_insensitive'] ?? false),
        );
    }
}
