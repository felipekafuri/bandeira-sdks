<?php

declare(strict_types=1);

namespace Bandeira\Internal;

final class Strings
{
    /** @return list<string> */
    public static function splitMulti(string $value): array
    {
        $normalized = str_replace(["\r\n", "\n"], ',', $value);
        $parts = explode(',', $normalized);

        $result = [];
        foreach ($parts as $part) {
            $trimmed = trim($part);
            if ($trimmed !== '') {
                $result[] = $trimmed;
            }
        }

        return $result;
    }
}
