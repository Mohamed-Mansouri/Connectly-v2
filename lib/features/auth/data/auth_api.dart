import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/auth_models.dart';

class AuthApi implements AuthRepository {
  AuthApi({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ??
            Uri.parse(const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'http://127.0.0.1:8787',
            )) {
    if (!['http', 'https'].contains(_baseUri.scheme) ||
        _baseUri.host.isEmpty ||
        _baseUri.userInfo.isNotEmpty) {
      throw ArgumentError('Configure a valid API_BASE_URL.');
    }
    if (kReleaseMode && _baseUri.scheme != 'https') {
      throw ArgumentError('Release builds require an HTTPS API_BASE_URL.');
    }
  }

  final http.Client _client;
  final Uri _baseUri;

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? body,
    String? token,
  }) async {
    try {
      final request = http.Request(method, _baseUri.resolve(path));
      request.headers['Accept'] = 'application/json';
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 15)),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 204) return {};
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AuthException(
          (decoded['error'] as Map<String, dynamic>?)?['message'] as String? ??
              'The request failed. Please try again.',
          statusCode: response.statusCode,
        );
      }
      return decoded;
    } on TimeoutException {
      throw const AuthException('The connection timed out. Please try again.');
    } on http.ClientException {
      throw const AuthException(
        'We couldn\'t connect. Check your connection and try again.',
      );
    } on FormatException {
      throw const AuthException(
          'The service is unavailable. Please try again.');
    } on TypeError {
      throw const AuthException(
          'The service is unavailable. Please try again.');
    }
  }

  AuthSession _session(Map<String, dynamic> json) {
    try {
      return AuthSession(
        token: json['token'] as String,
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      );
    } on Object {
      throw const AuthException(
          'The service is unavailable. Please try again.');
    }
  }

  @override
  Future<AuthSession> signIn(String email, String password) async => _session(
        await _request('POST', '/auth/login', body: {
          'email': email,
          'password': password,
        }),
      );

  @override
  Future<AuthSession> signUp(
          String name, String email, String password) async =>
      _session(await _request('POST', '/auth/signup', body: {
        'name': name,
        'email': email,
        'password': password,
      }));

  @override
  Future<AuthUser> currentUser(String token) async {
    final data = await _request('GET', '/me', token: token);
    try {
      return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    } on Object {
      throw const AuthException(
          'The service is unavailable. Please try again.');
    }
  }

  @override
  Future<void> signOut(String token) async {
    await _request('POST', '/auth/logout', token: token);
  }

  void close() => _client.close();
}
