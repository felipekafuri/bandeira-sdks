<?php

declare(strict_types=1);

namespace Bandeira\Internal;

use Bandeira\Context;
use DateTimeImmutable;
use DateTimeInterface;
use DateTimeZone;

final class Evaluator
{
    public static function evaluateStrategy(Strategy $strategy, Context $ctx): bool
    {
        foreach ($strategy->constraints as $constraint) {
            if (!self::evaluateConstraint($constraint, $ctx)) {
                return false;
            }
        }

        return match ($strategy->name) {
            'default' => true,
            'userWithId' => self::evalUserWithId($strategy, $ctx),
            'gradualRollout' => self::evalGradualRollout($strategy, $ctx),
            'remoteAddress' => self::evalRemoteAddress($strategy, $ctx),
            default => true,
        };
    }

    private static function evalUserWithId(Strategy $strategy, Context $ctx): bool
    {
        $userIds = $strategy->parameters['userIds'] ?? null;
        if (!is_string($userIds)) {
            return false;
        }

        foreach (Strings::splitMulti($userIds) as $id) {
            if ($id === $ctx->userId) {
                return true;
            }
        }

        return false;
    }

    private static function evalGradualRollout(Strategy $strategy, Context $ctx): bool
    {
        $rollout = self::parseRollout($strategy->parameters['rollout'] ?? null);
        if ($rollout === null) {
            return false;
        }

        if ($rollout >= 100) {
            return true;
        }

        if ($rollout <= 0) {
            return false;
        }

        $stickiness = is_string($strategy->parameters['stickiness'] ?? null)
            ? $strategy->parameters['stickiness']
            : 'userId';

        $stickinessValue = match ($stickiness) {
            'userId' => $ctx->userId,
            'sessionId' => $ctx->sessionId,
            default => $ctx->properties[$stickiness] ?? '',
        };

        if ($stickinessValue === '') {
            return false;
        }

        $groupId = is_string($strategy->parameters['groupId'] ?? null)
            ? $strategy->parameters['groupId']
            : '';

        return Hash::normalizedHash($stickinessValue . $groupId) < $rollout;
    }

    private static function evalRemoteAddress(Strategy $strategy, Context $ctx): bool
    {
        $ips = $strategy->parameters['ips'] ?? $strategy->parameters['IPs'] ?? null;
        if (!is_string($ips)) {
            return false;
        }

        $address = $ctx->remoteAddress;
        foreach (Strings::splitMulti($ips) as $entry) {
            if ($entry === $address) {
                return true;
            }
            if (str_ends_with($entry, '.') && str_starts_with($address, $entry)) {
                return true;
            }
        }

        return false;
    }

    private static function evaluateConstraint(Constraint $constraint, Context $ctx): bool
    {
        $ctxValue = self::getContextValue($constraint->contextName, $ctx);
        $result = self::evalOperator(
            $constraint->operator,
            $ctxValue,
            $constraint->values,
            $constraint->caseInsensitive,
        );

        if ($constraint->inverted) {
            return !$result;
        }

        return $result;
    }

    private static function getContextValue(string $name, Context $ctx): string
    {
        return match ($name) {
            'userId' => $ctx->userId,
            'sessionId' => $ctx->sessionId,
            'remoteAddress' => $ctx->remoteAddress,
            default => $ctx->properties[$name] ?? '',
        };
    }

    /**
     * @param list<string> $values
     */
    private static function evalOperator(string $operator, string $ctxValue, array $values, bool $caseInsensitive): bool
    {
        $cv = $caseInsensitive ? strtolower($ctxValue) : $ctxValue;
        $normalize = static fn (string $value): string => $caseInsensitive ? strtolower($value) : $value;

        return match ($operator) {
            'IN' => self::any($values, static fn (string $value): bool => $cv === $normalize($value)),
            'NOT_IN' => self::all($values, static fn (string $value): bool => $cv !== $normalize($value)),
            'STR_CONTAINS' => self::any($values, static fn (string $value): bool => str_contains($cv, $normalize($value))),
            'STR_STARTS_WITH' => self::any($values, static fn (string $value): bool => str_starts_with($cv, $normalize($value))),
            'STR_ENDS_WITH' => self::any($values, static fn (string $value): bool => str_ends_with($cv, $normalize($value))),
            'NUM_EQ', 'NUM_GT', 'NUM_GTE', 'NUM_LT', 'NUM_LTE' => self::evalNumeric($operator, $cv, $values),
            'DATE_AFTER', 'DATE_BEFORE' => self::evalDate($operator, $cv, $values),
            default => false,
        };
    }

    /**
     * @param list<string> $values
     */
    private static function evalNumeric(string $operator, string $ctxValue, array $values): bool
    {
        if (!is_numeric($ctxValue)) {
            return false;
        }

        $number = (float) $ctxValue;
        foreach ($values as $value) {
            if (!is_numeric($value)) {
                continue;
            }

            $target = (float) $value;
            $result = match ($operator) {
                'NUM_EQ' => $number === $target,
                'NUM_GT' => $number > $target,
                'NUM_GTE' => $number >= $target,
                'NUM_LT' => $number < $target,
                'NUM_LTE' => $number <= $target,
                default => false,
            };

            if ($result) {
                return true;
            }
        }

        return false;
    }

    /**
     * @param list<string> $values
     */
    private static function evalDate(string $operator, string $ctxValue, array $values): bool
    {
        $time = self::parseDate($ctxValue);
        if ($time === null) {
            return false;
        }

        foreach ($values as $value) {
            $target = self::parseDate($value);
            if ($target === null) {
                continue;
            }

            if ($operator === 'DATE_AFTER' && $time > $target) {
                return true;
            }

            if ($operator === 'DATE_BEFORE' && $time < $target) {
                return true;
            }
        }

        return false;
    }

    private static function parseDate(string $value): ?DateTimeImmutable
    {
        $date = DateTimeImmutable::createFromFormat(DateTimeInterface::RFC3339, $value);
        if ($date !== false) {
            return $date;
        }

        $date = DateTimeImmutable::createFromFormat('Y-m-d\\TH:i:s\\Z', $value, new DateTimeZone('UTC'));
        if ($date !== false) {
            return $date;
        }

        return null;
    }

    private static function parseRollout(mixed $value): ?int
    {
        if (is_int($value)) {
            return $value;
        }

        if (is_float($value)) {
            return (int) $value;
        }

        if (is_string($value) && preg_match('/^-?\d+$/', $value) === 1) {
            return (int) $value;
        }

        return null;
    }

    /**
     * @param list<string> $values
     */
    private static function any(array $values, callable $fn): bool
    {
        foreach ($values as $value) {
            if ($fn($value)) {
                return true;
            }
        }

        return false;
    }

    /**
     * @param list<string> $values
     */
    private static function all(array $values, callable $fn): bool
    {
        foreach ($values as $value) {
            if (!$fn($value)) {
                return false;
            }
        }

        return true;
    }
}
