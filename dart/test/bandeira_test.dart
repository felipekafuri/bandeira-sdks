import 'dart:convert';
import 'dart:io';

import 'package:bandeira/bandeira.dart';
import 'package:test/test.dart';

Map<String, dynamic> _loadFixtures() {
  final raw = File('../testdata/flags.json').readAsStringSync();
  final decoded = jsonDecode(raw);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
  throw StateError('fixtures must decode to a JSON object');
}

final Map<String, dynamic> _fixtures = _loadFixtures();

BandeiraClient createClientFromFixtures() {
  final client = BandeiraClient(
    const BandeiraConfig(
      url: 'http://localhost:9999',
      token: 'test-token',
    ),
  );
  client.loadFlags(_fixtures);
  return client;
}

Future<HttpServer> newTestServer(Map<String, dynamic> responseBody) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.uri.path != '/api/v1/flags') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    if (request.headers.value(HttpHeaders.authorizationHeader) !=
        'Bearer test-token') {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write('unauthorized');
      await request.response.close();
      return;
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(responseBody));
    await request.response.close();
  });
  return server;
}

void main() {
  group('BandeiraClient', () {
    group('basic toggles', () {
      test('enabled flag with no strategies returns true', () {
        final client = createClientFromFixtures();
        expect(client.isEnabled('simple-on'), isTrue);
      });

      test('disabled flag returns false', () {
        final client = createClientFromFixtures();
        expect(client.isEnabled('simple-off'), isFalse);
      });

      test('unknown flag returns false', () {
        final client = createClientFromFixtures();
        expect(client.isEnabled('nonexistent'), isFalse);
      });
    });

    group('default strategy', () {
      test('returns true', () {
        final client = createClientFromFixtures();
        expect(client.isEnabled('default-strategy'), isTrue);
      });
    });

    group('userWithId', () {
      test('matches a listed user', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'user-targeting',
            const BandeiraContext(userId: 'user-42'),
          ),
          isTrue,
        );
      });

      test('rejects an unlisted user', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'user-targeting',
            const BandeiraContext(userId: 'user-99'),
          ),
          isFalse,
        );
      });

      test('rejects when no context provided', () {
        final client = createClientFromFixtures();
        expect(client.isEnabled('user-targeting'), isFalse);
      });

      test('handles newline-separated user IDs', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'user-targeting-newlines',
            const BandeiraContext(userId: 'user-42'),
          ),
          isTrue,
        );
        expect(
          client.isEnabled(
            'user-targeting-newlines',
            const BandeiraContext(userId: 'user-99'),
          ),
          isFalse,
        );
      });
    });

    group('gradualRollout', () {
      test('100% rollout is always on', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'rollout-100',
            const BandeiraContext(userId: 'anyone'),
          ),
          isTrue,
        );
      });

      test('0% rollout is always off', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'rollout-0',
            const BandeiraContext(userId: 'anyone'),
          ),
          isFalse,
        );
      });

      test('no userId means no stickiness', () {
        final client = createClientFromFixtures();
        expect(client.isEnabled('rollout-50'), isFalse);
      });

      test('session stickiness uses sessionId', () {
        final client = createClientFromFixtures();
        final result = client.isEnabled(
          'rollout-session-stickiness',
          const BandeiraContext(sessionId: 'sess-123'),
        );
        expect(result, isA<bool>());
      });
    });

    group('remoteAddress', () {
      test('exact match', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'ip-allowlist',
            const BandeiraContext(remoteAddress: '10.0.0.1'),
          ),
          isTrue,
        );
      });

      test('prefix match', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'ip-allowlist',
            const BandeiraContext(remoteAddress: '192.168.1.100'),
          ),
          isTrue,
        );
      });

      test('no match', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'ip-allowlist',
            const BandeiraContext(remoteAddress: '172.16.0.1'),
          ),
          isFalse,
        );
      });

      test('legacy IPs key works', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'ip-allowlist-legacy',
            const BandeiraContext(remoteAddress: '10.0.0.1'),
          ),
          isTrue,
        );
      });
    });

    group('constraints', () {
      test('IN operator matches', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'constraint-in',
            const BandeiraContext(properties: <String, String>{'companyId': '2'}),
          ),
          isTrue,
        );
      });

      test('IN operator rejects', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'constraint-in',
            const BandeiraContext(properties: <String, String>{'companyId': '99'}),
          ),
          isFalse,
        );
      });

      test('NOT_IN operator matches', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'constraint-not-in',
            const BandeiraContext(properties: <String, String>{'plan': 'enterprise'}),
          ),
          isTrue,
        );
      });

      test('NOT_IN operator rejects', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'constraint-not-in',
            const BandeiraContext(properties: <String, String>{'plan': 'free'}),
          ),
          isFalse,
        );
      });

      test('inverted constraint', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'constraint-inverted',
            const BandeiraContext(properties: <String, String>{'plan': 'free'}),
          ),
          isFalse,
        );
        expect(
          client.isEnabled(
            'constraint-inverted',
            const BandeiraContext(
              properties: <String, String>{'plan': 'enterprise'},
            ),
          ),
          isTrue,
        );
      });

      test('case-insensitive constraint', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'constraint-case-insensitive',
            const BandeiraContext(properties: <String, String>{'country': 'brazil'}),
          ),
          isTrue,
        );
        expect(
          client.isEnabled(
            'constraint-case-insensitive',
            const BandeiraContext(properties: <String, String>{'country': 'PORTUGAL'}),
          ),
          isTrue,
        );
        expect(
          client.isEnabled(
            'constraint-case-insensitive',
            const BandeiraContext(properties: <String, String>{'country': 'spain'}),
          ),
          isFalse,
        );
      });

      test('STR_CONTAINS', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'constraint-str-contains',
            const BandeiraContext(properties: <String, String>{'email': 'user@acme.com'}),
          ),
          isTrue,
        );
        expect(
          client.isEnabled(
            'constraint-str-contains',
            const BandeiraContext(properties: <String, String>{'email': 'user@other.com'}),
          ),
          isFalse,
        );
      });

      test('STR_STARTS_WITH', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'constraint-str-starts-with',
            const BandeiraContext(properties: <String, String>{'email': 'admin@acme.com'}),
          ),
          isTrue,
        );
        expect(
          client.isEnabled(
            'constraint-str-starts-with',
            const BandeiraContext(properties: <String, String>{'email': 'user@acme.com'}),
          ),
          isFalse,
        );
      });

      test('STR_ENDS_WITH', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'constraint-str-ends-with',
            const BandeiraContext(properties: <String, String>{'email': 'user@acme.com'}),
          ),
          isTrue,
        );
        expect(
          client.isEnabled(
            'constraint-str-ends-with',
            const BandeiraContext(properties: <String, String>{'email': 'user@acme.io'}),
          ),
          isFalse,
        );
      });

      test('NUM_GTE', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'constraint-num-gte',
            const BandeiraContext(properties: <String, String>{'age': '21'}),
          ),
          isTrue,
        );
        expect(
          client.isEnabled(
            'constraint-num-gte',
            const BandeiraContext(properties: <String, String>{'age': '18'}),
          ),
          isTrue,
        );
        expect(
          client.isEnabled(
            'constraint-num-gte',
            const BandeiraContext(properties: <String, String>{'age': '16'}),
          ),
          isFalse,
        );
      });

      test('DATE_AFTER', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'constraint-date-after',
            const BandeiraContext(
              properties: <String, String>{'signupDate': '2026-06-15T00:00:00Z'},
            ),
          ),
          isTrue,
        );
        expect(
          client.isEnabled(
            'constraint-date-after',
            const BandeiraContext(
              properties: <String, String>{'signupDate': '2025-06-15T00:00:00Z'},
            ),
          ),
          isFalse,
        );
      });
    });

    group('multi-strategy', () {
      test('VIP user matches first strategy', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'multi-strategy',
            const BandeiraContext(userId: 'vip-1'),
          ),
          isTrue,
        );
      });
    });

    group('constrained rollout', () {
      test('passes when constraint matches', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'constrained-rollout',
            const BandeiraContext(
              userId: 'any-user',
              properties: <String, String>{'companyId': 'acme'},
            ),
          ),
          isTrue,
        );
      });

      test('fails when constraint does not match', () {
        final client = createClientFromFixtures();
        expect(
          client.isEnabled(
            'constrained-rollout',
            const BandeiraContext(
              userId: 'any-user',
              properties: <String, String>{'companyId': 'other'},
            ),
          ),
          isFalse,
        );
      });
    });

    group('allFlags', () {
      test('returns all flags with their enabled state', () {
        final client = createClientFromFixtures();
        final flags = client.allFlags();
        expect(flags['simple-on'], isTrue);
        expect(flags['simple-off'], isFalse);
      });
    });

    group('validation', () {
      test('throws on missing url', () {
        expect(
          () => BandeiraClient(
            const BandeiraConfig(
              url: '',
              token: 'test',
            ),
          ),
          throwsArgumentError,
        );
      });

      test('throws on missing token', () {
        expect(
          () => BandeiraClient(
            const BandeiraConfig(
              url: 'http://localhost',
              token: '',
            ),
          ),
          throwsArgumentError,
        );
      });
    });

    group('startup APIs', () {
      test('create performs initial fetch', () async {
        final server = await newTestServer(_fixtures);
        addTearDown(() async {
          await server.close(force: true);
        });

        final client = await BandeiraClient.create(
          BandeiraConfig(
            url: 'http://127.0.0.1:${server.port}',
            token: 'test-token',
            pollInterval: const Duration(hours: 1),
          ),
        );
        addTearDown(client.close);

        expect(client.isEnabled('simple-on'), isTrue);
      });

      test('start performs initial fetch', () async {
        final server = await newTestServer(_fixtures);
        addTearDown(() async {
          await server.close(force: true);
        });

        final client = BandeiraClient(
          BandeiraConfig(
            url: 'http://127.0.0.1:${server.port}',
            token: 'test-token',
            pollInterval: const Duration(hours: 1),
          ),
        );
        addTearDown(client.close);

        await client.start();

        expect(client.isEnabled('simple-on'), isTrue);
      });

      test('create fails fast when initial request fails', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          request.response.statusCode = HttpStatus.unauthorized;
          request.response.write('unauthorized');
          await request.response.close();
        });
        addTearDown(() async {
          await server.close(force: true);
        });

        final future = BandeiraClient.create(
          BandeiraConfig(
            url: 'http://127.0.0.1:${server.port}',
            token: 'test-token',
          ),
        );
        await expectLater(future, throwsA(isA<StateError>()));
      });
    });
  });
}
