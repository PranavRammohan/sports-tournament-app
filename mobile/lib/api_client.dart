// api_client.dart
// Thin wrapper around package:http that centralizes the boilerplate every
// screen used to repeat by hand: reading the JWT from SharedPreferences,
// attaching it as a bearer token, and JSON-decoding the response. Also
// centralizes 401 handling — an expired/invalid token clears the session
// and bounces the user back to login instead of each screen failing
// silently or showing a confusing error.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'main.dart' show navigatorKey;

class ApiResponse {
  final int statusCode;
  final dynamic data;

  ApiResponse(this.statusCode, this.data);

  String get error => (data is Map && data['error'] is String)
      ? data['error']
      : 'Something went wrong.';

  // Like [error], but lets each call site supply its own more specific
  // fallback message instead of the generic default.
  String errorOr(String fallback) =>
      (data is Map && data['error'] is String) ? data['error'] : fallback;
}

class ApiClient {
  static Future<ApiResponse> get(
    String path, {
    Map<String, String>? queryParams,
  }) => _request('GET', path, queryParams: queryParams);

  static Future<ApiResponse> post(String path, {dynamic body}) =>
      _request('POST', path, body: body);

  static Future<ApiResponse> put(String path, {dynamic body}) =>
      _request('PUT', path, body: body);

  static Future<ApiResponse> patch(
    String path, {
    dynamic body,
    bool skipAuthRedirect = false,
  }) => _request('PATCH', path, body: body, skipAuthRedirect: skipAuthRedirect);

  static Future<ApiResponse> delete(String path, {dynamic body}) =>
      _request('DELETE', path, body: body);

  static Future<ApiResponse> _request(
    String method,
    String path, {
    dynamic body,
    Map<String, String>? queryParams,
    bool skipAuthRedirect = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');

    var uri = Uri.parse('$baseApiUrl$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams);
    }

    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final encodedBody = body != null ? jsonEncode(body) : null;

    http.Response response;
    switch (method) {
      case 'GET':
        response = await http.get(uri, headers: headers);
        break;
      case 'POST':
        response = await http.post(uri, headers: headers, body: encodedBody);
        break;
      case 'PUT':
        response = await http.put(uri, headers: headers, body: encodedBody);
        break;
      case 'PATCH':
        response = await http.patch(uri, headers: headers, body: encodedBody);
        break;
      case 'DELETE':
        response = await http.delete(
          uri,
          headers: headers,
          body: encodedBody,
        );
        break;
      default:
        throw ArgumentError('Unsupported method $method');
    }

    dynamic data;
    if (response.body.isNotEmpty) {
      try {
        data = jsonDecode(response.body);
      } catch (_) {
        data = null;
      }
    }

    if (response.statusCode == 401 && !skipAuthRedirect) {
      await prefs.remove('authToken');
      await prefs.remove('user');
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
    }

    return ApiResponse(response.statusCode, data);
  }
}
