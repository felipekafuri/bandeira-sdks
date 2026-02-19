<?php

declare(strict_types=1);

namespace Bandeira\Tests;

use Bandeira\Client;
use Bandeira\Config;
use Bandeira\Exception\ConfigurationException;
use PHPUnit\Framework\TestCase;

final class ClientValidationTest extends TestCase
{
    public function testMissingUrlThrows(): void
    {
        $this->expectException(ConfigurationException::class);
        new Client(new Config(url: '', token: 'test-token'));
    }

    public function testMissingTokenThrows(): void
    {
        $this->expectException(ConfigurationException::class);
        new Client(new Config(url: 'http://localhost:8080', token: ''));
    }
}
