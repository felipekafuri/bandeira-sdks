<?php

declare(strict_types=1);

namespace Bandeira\Tests\TestHelpers;

final class FixtureLoader
{
    /** @return array<string, mixed> */
    public static function flags(): array
    {
        $raw = file_get_contents(dirname(__DIR__, 3) . '/testdata/flags.json');
        if ($raw === false) {
            throw new \RuntimeException('failed to load test fixtures');
        }

        $decoded = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
        if (!is_array($decoded)) {
            throw new \RuntimeException('invalid fixture format');
        }

        return $decoded;
    }
}
