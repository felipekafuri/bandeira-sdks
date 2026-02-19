<?php

declare(strict_types=1);

namespace Bandeira\Internal;

final class Parser
{
    /**
     * @param array<string, mixed> $response
     * @return array<string, Flag>
     */
    public static function parseFlags(array $response): array
    {
        $result = [];

        $rawFlags = $response['flags'] ?? [];
        if (!is_array($rawFlags)) {
            return $result;
        }

        foreach ($rawFlags as $rawFlag) {
            if (!is_array($rawFlag)) {
                continue;
            }

            $flag = Flag::fromArray($rawFlag);
            if ($flag === null) {
                continue;
            }

            $result[$flag->name] = $flag;
        }

        return $result;
    }
}
