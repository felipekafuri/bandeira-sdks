<?php

declare(strict_types=1);

namespace Bandeira\Tests;

use Bandeira\Client;
use Bandeira\Config;
use Bandeira\Context;
use Bandeira\Tests\TestHelpers\FixtureLoader;
use PHPUnit\Framework\TestCase;

final class ClientEvaluationTest extends TestCase
{
    /** @var array<string, mixed> */
    private array $fixtures;

    protected function setUp(): void
    {
        parent::setUp();
        $this->fixtures = FixtureLoader::flags();
    }

    private function createClient(): Client
    {
        $client = new Client(new Config(
            url: 'http://localhost:9999',
            token: 'test-token',
        ));
        $client->loadFlags($this->fixtures);

        return $client;
    }

    public function testEnabledFlagWithNoStrategiesReturnsTrue(): void
    {
        $c = $this->createClient();
        self::assertTrue($c->isEnabled('simple-on'));
    }

    public function testDisabledFlagReturnsFalse(): void
    {
        $c = $this->createClient();
        self::assertFalse($c->isEnabled('simple-off'));
    }

    public function testUnknownFlagReturnsFalse(): void
    {
        $c = $this->createClient();
        self::assertFalse($c->isEnabled('nonexistent'));
    }

    public function testDefaultStrategyReturnsTrue(): void
    {
        $c = $this->createClient();
        self::assertTrue($c->isEnabled('default-strategy'));
    }

    public function testUserWithIdMatchesListedUser(): void
    {
        $c = $this->createClient();
        self::assertTrue($c->isEnabled('user-targeting', new Context(userId: 'user-42')));
    }

    public function testUserWithIdRejectsUnlistedUser(): void
    {
        $c = $this->createClient();
        self::assertFalse($c->isEnabled('user-targeting', new Context(userId: 'user-99')));
    }

    public function testUserWithIdRejectsNoContext(): void
    {
        $c = $this->createClient();
        self::assertFalse($c->isEnabled('user-targeting'));
    }

    public function testUserWithIdNewlineSeparated(): void
    {
        $c = $this->createClient();
        self::assertTrue($c->isEnabled('user-targeting-newlines', new Context(userId: 'user-42')));
        self::assertFalse($c->isEnabled('user-targeting-newlines', new Context(userId: 'user-99')));
    }

    public function testGradualRollout100Percent(): void
    {
        $c = $this->createClient();
        self::assertTrue($c->isEnabled('rollout-100', new Context(userId: 'anyone')));
    }

    public function testGradualRollout0Percent(): void
    {
        $c = $this->createClient();
        self::assertFalse($c->isEnabled('rollout-0', new Context(userId: 'anyone')));
    }

    public function testGradualRolloutWithoutStickinessReturnsFalse(): void
    {
        $c = $this->createClient();
        self::assertFalse($c->isEnabled('rollout-50'));
    }

    public function testSessionStickinessUsesSessionId(): void
    {
        $c = $this->createClient();
        self::assertIsBool($c->isEnabled('rollout-session-stickiness', new Context(sessionId: 'sess-123')));
    }

    public function testRemoteAddressExactMatch(): void
    {
        $c = $this->createClient();
        self::assertTrue($c->isEnabled('ip-allowlist', new Context(remoteAddress: '10.0.0.1')));
    }

    public function testRemoteAddressPrefixMatch(): void
    {
        $c = $this->createClient();
        self::assertTrue($c->isEnabled('ip-allowlist', new Context(remoteAddress: '192.168.1.100')));
    }

    public function testRemoteAddressNoMatch(): void
    {
        $c = $this->createClient();
        self::assertFalse($c->isEnabled('ip-allowlist', new Context(remoteAddress: '172.16.0.1')));
    }

    public function testRemoteAddressLegacyKeyWorks(): void
    {
        $c = $this->createClient();
        self::assertTrue($c->isEnabled('ip-allowlist-legacy', new Context(remoteAddress: '10.0.0.1')));
    }

    public function testConstraintInOperatorMatches(): void
    {
        $c = $this->createClient();
        self::assertTrue($c->isEnabled('constraint-in', new Context(properties: ['companyId' => '2'])));
    }

    public function testConstraintNotInOperatorMatches(): void
    {
        $c = $this->createClient();
        self::assertTrue($c->isEnabled('constraint-not-in', new Context(properties: ['plan' => 'enterprise'])));
    }

    public function testConstraintInverted(): void
    {
        $c = $this->createClient();
        self::assertFalse($c->isEnabled('constraint-inverted', new Context(properties: ['plan' => 'free'])));
        self::assertTrue($c->isEnabled('constraint-inverted', new Context(properties: ['plan' => 'enterprise'])));
    }

    public function testConstraintCaseInsensitive(): void
    {
        $c = $this->createClient();
        self::assertTrue($c->isEnabled('constraint-case-insensitive', new Context(properties: ['country' => 'brazil'])));
        self::assertTrue($c->isEnabled('constraint-case-insensitive', new Context(properties: ['country' => 'PORTUGAL'])));
        self::assertFalse($c->isEnabled('constraint-case-insensitive', new Context(properties: ['country' => 'spain'])));
    }

    public function testConstraintStringOperators(): void
    {
        $c = $this->createClient();
        self::assertTrue($c->isEnabled('constraint-str-contains', new Context(properties: ['email' => 'user@acme.com'])));
        self::assertTrue($c->isEnabled('constraint-str-starts-with', new Context(properties: ['email' => 'admin@acme.com'])));
        self::assertTrue($c->isEnabled('constraint-str-ends-with', new Context(properties: ['email' => 'user@acme.com'])));
        self::assertFalse($c->isEnabled('constraint-str-contains', new Context(properties: ['email' => 'user@other.com'])));
    }

    public function testConstraintNumGte(): void
    {
        $c = $this->createClient();
        self::assertTrue($c->isEnabled('constraint-num-gte', new Context(properties: ['age' => '21'])));
        self::assertFalse($c->isEnabled('constraint-num-gte', new Context(properties: ['age' => '16'])));
    }

    public function testConstraintDateAfter(): void
    {
        $c = $this->createClient();
        self::assertTrue($c->isEnabled('constraint-date-after', new Context(properties: ['signupDate' => '2026-06-15T00:00:00Z'])));
        self::assertFalse($c->isEnabled('constraint-date-after', new Context(properties: ['signupDate' => '2025-06-15T00:00:00Z'])));
    }

    public function testMultiStrategyOrLogic(): void
    {
        $c = $this->createClient();
        self::assertTrue($c->isEnabled('multi-strategy', new Context(userId: 'vip-1')));
    }

    public function testConstrainedRollout(): void
    {
        $c = $this->createClient();
        self::assertTrue($c->isEnabled('constrained-rollout', new Context(userId: 'any-user', properties: ['companyId' => 'acme'])));
        self::assertFalse($c->isEnabled('constrained-rollout', new Context(userId: 'any-user', properties: ['companyId' => 'other'])));
    }

    public function testAllFlagsReturnsSnapshot(): void
    {
        $c = $this->createClient();
        $flags = $c->allFlags();

        self::assertTrue($flags['simple-on']);
        self::assertFalse($flags['simple-off']);
    }
}
