import 'dart:convert';

import 'package:http/http.dart' as http;

import 'flag_models.dart';

class HttpFlagsRepository {
  HttpFlagsRepository({
    required String url,
    required String token,
    required http.Client httpClient,
  })  : _url = _trimTrailingSlashes(url),
        _token = token,
        _httpClient = httpClient;

  final String _url;
  final String _token;
  final http.Client _httpClient;

  Future<Map<String, Flag>> fetchFlags() async {
    final response = await _httpClient.get(
      Uri.parse('$_url/api/v1/flags'),
      headers: <String, String>{
        'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode != 200) {
      throw StateError(
        'bandeira: unexpected status ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = _decodeBody(response.body);
    final apiResponse = ApiResponse.fromJson(decoded);
    final byName = <String, Flag>{};
    for (final flag in apiResponse.flags) {
      byName[flag.name] = flag;
    }
    return byName;
  }

  Map<String, dynamic> _decodeBody(String body) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (error) {
      throw StateError('bandeira: failed to decode response: $error');
    }

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    throw StateError('bandeira: failed to decode response: expected object');
  }
}

String _trimTrailingSlashes(String value) => value.replaceFirst(RegExp(r'/+$'), '');
