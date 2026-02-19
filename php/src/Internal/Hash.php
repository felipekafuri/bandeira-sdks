<?php

declare(strict_types=1);

namespace Bandeira\Internal;

final class Hash
{
    public static function normalizedHash(string $value): int
    {
        $hash = 0x811C9DC5;
        $bytes = unpack('C*', $value);
        if ($bytes === false) {
            return 0;
        }

        foreach ($bytes as $byte) {
            $hash ^= $byte;
            $hash = ($hash * 0x01000193) & 0xFFFFFFFF;
        }

        return $hash % 100;
    }
}
