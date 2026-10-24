import 'dart:convert';

import 'package:shelf/shelf.dart';

const _jsonHeaders = {'Content-Type': 'application/json'};

Response jsonOk(Object body) =>
    Response.ok(jsonEncode(body), headers: _jsonHeaders);

Response jsonError(String message, {required int status}) => Response(
  status,
  body: jsonEncode({'error': message}),
  headers: _jsonHeaders,
);

extension AgentApiRequestBody on Request {
  Future<Map<String, dynamic>> readJsonObject() async {
    final bodyText = await readAsString();
    if (bodyText.trim().isEmpty) return {};
    final decoded = jsonDecode(bodyText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Body must be a JSON object.');
    }
    return decoded;
  }
}

extension AgentApiJsonFields on Map<String, dynamic> {
  String requiredString(String key) {
    final value = this[key];
    if (value is! String || value.trim().isEmpty) {
      throw ArgumentError('"$key" is required.');
    }
    return value.trim();
  }

  List<String> requiredStringList(String key) {
    final value = this[key];
    if (value is! List || value.isEmpty) {
      throw ArgumentError('"$key" must be a non-empty list of ids.');
    }
    return [for (final element in value) element as String];
  }
}
