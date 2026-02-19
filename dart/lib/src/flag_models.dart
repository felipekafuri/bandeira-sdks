class ApiResponse {
  ApiResponse({required this.flags});

  final List<Flag> flags;

  factory ApiResponse.fromJson(Map<String, dynamic> json) {
    final flagsRaw = json['flags'];
    final flagsList = flagsRaw is List ? flagsRaw : const [];
    return ApiResponse(
      flags: flagsList
          .whereType<Map>()
          .map(
            (raw) => Flag.fromJson(
              raw.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class Flag {
  Flag({
    required this.name,
    required this.enabled,
    required this.strategies,
  });

  final String name;
  final bool enabled;
  final List<Strategy> strategies;

  factory Flag.fromJson(Map<String, dynamic> json) {
    final strategiesRaw = json['strategies'];
    final strategiesList = strategiesRaw is List ? strategiesRaw : const [];
    return Flag(
      name: json['name'] is String ? json['name'] as String : '',
      enabled: json['enabled'] is bool ? json['enabled'] as bool : false,
      strategies: strategiesList
          .whereType<Map>()
          .map(
            (raw) => Strategy.fromJson(
              raw.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class Strategy {
  Strategy({
    required this.name,
    required this.parameters,
    required this.constraints,
  });

  final String name;
  final Map<String, dynamic> parameters;
  final List<Constraint> constraints;

  factory Strategy.fromJson(Map<String, dynamic> json) {
    final constraintsRaw = json['constraints'];
    final constraintsList = constraintsRaw is List ? constraintsRaw : const [];
    final parametersRaw = json['parameters'];
    return Strategy(
      name: json['name'] is String ? json['name'] as String : '',
      parameters: parametersRaw is Map
          ? parametersRaw.map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : <String, dynamic>{},
      constraints: constraintsList
          .whereType<Map>()
          .map(
            (raw) => Constraint.fromJson(
              raw.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class Constraint {
  Constraint({
    required this.contextName,
    required this.operator,
    required this.values,
    required this.inverted,
    required this.caseInsensitive,
  });

  final String contextName;
  final String operator;
  final List<String> values;
  final bool inverted;
  final bool caseInsensitive;

  factory Constraint.fromJson(Map<String, dynamic> json) {
    final valuesRaw = json['values'];
    final valuesList = valuesRaw is List ? valuesRaw : const [];
    return Constraint(
      contextName: json['context_name'] is String
          ? json['context_name'] as String
          : '',
      operator: json['operator'] is String ? json['operator'] as String : '',
      values: valuesList.map((value) => value.toString()).toList(growable: false),
      inverted: json['inverted'] is bool ? json['inverted'] as bool : false,
      caseInsensitive: json['case_insensitive'] is bool
          ? json['case_insensitive'] as bool
          : false,
    );
  }
}
