import 'dart:async';

import 'package:http/http.dart' as http;

import 'evaluator.dart';
import 'flag_models.dart';
import 'http_flags_repository.dart';
import 'models.dart';

class BandeiraClient {
  BandeiraClient(
    BandeiraConfig config, {
    http.Client? httpClient,
  })  : _config = _validateConfig(config),
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null {
    _repository = HttpFlagsRepository(
      url: _config.url,
      token: _config.token,
      httpClient: _httpClient,
    );
  }

  static Future<BandeiraClient> create(
    BandeiraConfig config, {
    http.Client? httpClient,
  }) async {
    final client = BandeiraClient(config, httpClient: httpClient);
    try {
      await client.start();
      return client;
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  final BandeiraConfig _config;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  late final HttpFlagsRepository _repository;

  Map<String, Flag> _flags = <String, Flag>{};
  Timer? _pollTimer;
  bool _started = false;
  bool _closed = false;
  bool _polling = false;

  Future<void> start() async {
    if (_closed) {
      throw StateError('bandeira: client is closed');
    }
    if (_started) {
      return;
    }

    await _refreshFlags();
    _started = true;
    _pollTimer = Timer.periodic(_config.pollInterval, (_) {
      unawaited(_pollOnce());
    });
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  bool isEnabled(String name, [BandeiraContext? context]) {
    final flag = _flags[name];
    if (flag == null) {
      return false;
    }
    return isFlagEnabled(flag, context ?? const BandeiraContext());
  }

  Map<String, bool> allFlags() {
    return Map<String, bool>.unmodifiable(
      _flags.map((name, flag) => MapEntry(name, flag.enabled)),
    );
  }

  void loadFlags(Map<String, dynamic> response) {
    final parsed = ApiResponse.fromJson(response);
    final byName = <String, Flag>{};
    for (final flag in parsed.flags) {
      byName[flag.name] = flag;
    }
    _flags = byName;
  }

  Future<void> _pollOnce() async {
    if (_closed || _polling) {
      return;
    }
    _polling = true;
    try {
      await _refreshFlags();
    } catch (_) {
      // Keep last known flags on polling errors.
    } finally {
      _polling = false;
    }
  }

  Future<void> _refreshFlags() async {
    final fetched = await _repository.fetchFlags();
    _flags = fetched;
  }
}

BandeiraConfig _validateConfig(BandeiraConfig config) {
  if (config.url.trim().isEmpty) {
    throw ArgumentError('bandeira: url is required');
  }
  if (config.token.trim().isEmpty) {
    throw ArgumentError('bandeira: token is required');
  }
  if (config.pollInterval <= Duration.zero) {
    throw ArgumentError('bandeira: pollInterval must be positive');
  }
  return config;
}
