import 'dart:convert';

import 'flag_models.dart';
import 'models.dart';

bool isFlagEnabled(Flag flag, BandeiraContext context) {
  if (!flag.enabled) {
    return false;
  }

  if (flag.strategies.isEmpty) {
    return true;
  }

  for (final strategy in flag.strategies) {
    if (evaluateStrategy(strategy, context)) {
      return true;
    }
  }

  return false;
}

bool evaluateStrategy(Strategy strategy, BandeiraContext context) {
  for (final constraint in strategy.constraints) {
    if (!evaluateConstraint(constraint, context)) {
      return false;
    }
  }

  switch (strategy.name) {
    case 'default':
      return true;
    case 'userWithId':
      return _evalUserWithId(strategy, context);
    case 'gradualRollout':
      return _evalGradualRollout(strategy, context);
    case 'remoteAddress':
      return _evalRemoteAddress(strategy, context);
    default:
      return true;
  }
}

bool _evalUserWithId(Strategy strategy, BandeiraContext context) {
  final rawUserIds = strategy.parameters['userIds'];
  if (rawUserIds is! String) {
    return false;
  }

  return splitMulti(rawUserIds).contains(context.userId);
}

bool _evalGradualRollout(Strategy strategy, BandeiraContext context) {
  final rollout = _parseRollout(strategy.parameters['rollout']);
  if (rollout == null) {
    return false;
  }

  if (rollout >= 100) {
    return true;
  }
  if (rollout <= 0) {
    return false;
  }

  final stickiness = strategy.parameters['stickiness'] is String
      ? strategy.parameters['stickiness'] as String
      : 'userId';

  final stickinessValue = switch (stickiness) {
    'userId' => context.userId,
    'sessionId' => context.sessionId,
    _ => context.properties[stickiness] ?? '',
  };

  if (stickinessValue.isEmpty) {
    return false;
  }

  final groupId = strategy.parameters['groupId'] is String
      ? strategy.parameters['groupId'] as String
      : '';

  return normalizedHash('$stickinessValue$groupId') < rollout;
}

bool _evalRemoteAddress(Strategy strategy, BandeiraContext context) {
  var rawIps = strategy.parameters['ips'];
  rawIps ??= strategy.parameters['IPs'];
  if (rawIps is! String) {
    return false;
  }

  final remoteAddress = context.remoteAddress;
  for (final entry in splitMulti(rawIps)) {
    if (entry == remoteAddress) {
      return true;
    }
    if (entry.endsWith('.') && remoteAddress.startsWith(entry)) {
      return true;
    }
  }

  return false;
}

bool evaluateConstraint(Constraint constraint, BandeiraContext context) {
  final contextValue = _getContextValue(constraint.contextName, context);
  final result = _evaluateOperator(
    constraint.operator,
    contextValue,
    constraint.values,
    constraint.caseInsensitive,
  );
  return constraint.inverted ? !result : result;
}

String _getContextValue(String contextName, BandeiraContext context) {
  return switch (contextName) {
    'userId' => context.userId,
    'sessionId' => context.sessionId,
    'remoteAddress' => context.remoteAddress,
    _ => context.properties[contextName] ?? '',
  };
}

bool _evaluateOperator(
  String op,
  String contextValue,
  List<String> values,
  bool caseInsensitive,
) {
  final normalizedContextValue =
      caseInsensitive ? contextValue.toLowerCase() : contextValue;
  String normalize(String value) =>
      caseInsensitive ? value.toLowerCase() : value;

  switch (op) {
    case 'IN':
      return values.any((value) => normalizedContextValue == normalize(value));
    case 'NOT_IN':
      return values.every((value) => normalizedContextValue != normalize(value));
    case 'STR_CONTAINS':
      return values.any(
        (value) => normalizedContextValue.contains(normalize(value)),
      );
    case 'STR_STARTS_WITH':
      return values.any(
        (value) => normalizedContextValue.startsWith(normalize(value)),
      );
    case 'STR_ENDS_WITH':
      return values.any(
        (value) => normalizedContextValue.endsWith(normalize(value)),
      );
    case 'NUM_EQ':
    case 'NUM_GT':
    case 'NUM_GTE':
    case 'NUM_LT':
    case 'NUM_LTE':
      final number = double.tryParse(normalizedContextValue);
      if (number == null) {
        return false;
      }
      for (final value in values) {
        final target = double.tryParse(value);
        if (target == null) {
          continue;
        }
        final matches = switch (op) {
          'NUM_EQ' => number == target,
          'NUM_GT' => number > target,
          'NUM_GTE' => number >= target,
          'NUM_LT' => number < target,
          'NUM_LTE' => number <= target,
          _ => false,
        };
        if (matches) {
          return true;
        }
      }
      return false;
    case 'DATE_AFTER':
    case 'DATE_BEFORE':
      final valueDate = DateTime.tryParse(normalizedContextValue);
      if (valueDate == null) {
        return false;
      }
      for (final value in values) {
        final targetDate = DateTime.tryParse(value);
        if (targetDate == null) {
          continue;
        }
        final matches = op == 'DATE_AFTER'
            ? valueDate.isAfter(targetDate)
            : valueDate.isBefore(targetDate);
        if (matches) {
          return true;
        }
      }
      return false;
    default:
      return false;
  }
}

List<String> splitMulti(String value) {
  return value
      .replaceAll('\r\n', ',')
      .replaceAll('\n', ',')
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
}

int normalizedHash(String value) {
  var hash = 0x811C9DC5;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash % 100;
}

int? _parseRollout(dynamic rawRollout) {
  if (rawRollout is num) {
    return rawRollout.toInt();
  }
  if (rawRollout is String) {
    return int.tryParse(rawRollout);
  }
  return null;
}
