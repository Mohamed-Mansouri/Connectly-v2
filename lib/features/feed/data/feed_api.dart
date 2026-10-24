import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/feed_models.dart';

class FeedApi implements FeedRepository {
  FeedApi(
      {required String? Function() token, http.Client? client, Uri? baseUri})
      : _token = token,
        _client = client ?? http.Client(),
        _baseUri = baseUri ??
            Uri.parse(const String.fromEnvironment('API_BASE_URL',
                defaultValue: 'http://127.0.0.1:8787')) {
    if (!['http', 'https'].contains(_baseUri.scheme) ||
        _baseUri.host.isEmpty ||
        _baseUri.userInfo.isNotEmpty ||
        (kReleaseMode && _baseUri.scheme != 'https')) {
      throw ArgumentError(
          'Configure a valid API_BASE_URL (HTTPS for release).');
    }
  }

  final String? Function() _token;
  final http.Client _client;
  final Uri _baseUri;

  Future<Map<String, dynamic>> _request(String method, String path,
      {Map<String, String>? body, Map<String, String>? query}) async {
    final token = _token();
    if (token == null) {
      throw const FeedException('Sign in to see your feed.', statusCode: 401);
    }
    try {
      var uri = _baseUri.resolve(path);
      if (query != null) uri = uri.replace(queryParameters: query);
      final request = http.Request(method, uri);
      request.headers.addAll(
          {'Accept': 'application/json', 'Authorization': 'Bearer $token'});
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final response = await http.Response.fromStream(
              await _client.send(request).timeout(const Duration(seconds: 15)))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 204) return {};
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FeedException(
            (data['error'] as Map<String, dynamic>?)?['message'] as String? ??
                'Something went wrong. Please try again.',
            statusCode: response.statusCode);
      }
      return data;
    } on TimeoutException {
      throw const FeedException('The connection timed out. Please try again.');
    } on http.ClientException {
      throw const FeedException(
          'Could not connect. Check your connection and try again.');
    } on FormatException {
      throw const FeedException(
          'The service returned an unreadable response. Please try again.');
    } on TypeError {
      throw const FeedException(
          'The service returned an unreadable response. Please try again.');
    }
  }

  T _parse<T>(T Function() parse) {
    try {
      return parse();
    } on Object {
      throw const FeedException(
          'The service returned an unreadable response. Please try again.');
    }
  }

  @override
  Future<FeedPage> load({required String scope, String? cursor}) async {
    final data = await _request('GET', '/feed',
        query: {'scope': scope, if (cursor != null) 'cursor': cursor});
    return _parse(() => FeedPage(
        (data['posts'] as List)
            .map((p) => FeedPost.fromJson(p as Map<String, dynamic>))
            .toList(),
        data['nextCursor'] as String?));
  }

  @override
  Future<FeedPost> create(String body) async {
    final data = await _request('POST', '/posts', body: {'body': body.trim()});
    return _parse(
        () => FeedPost.fromJson(data['post'] as Map<String, dynamic>));
  }

  @override
  Future<void> delete(String postId) async {
    await _request('DELETE', '/posts/${Uri.encodeComponent(postId)}');
  }

  @override
  Future<FeedPost> react(String postId, String? kind) async {
    final data = await _request(kind == null ? 'DELETE' : 'PUT',
        '/posts/${Uri.encodeComponent(postId)}/reaction',
        body: kind == null ? null : {'kind': kind});
    return _parse(
        () => FeedPost.fromJson(data['post'] as Map<String, dynamic>));
  }

  @override
  Future<List<FeedPerson>> people(
      {String search = '', bool requests = false}) async {
    final data = await _request('GET', '/people',
        query: {'search': search.trim(), 'requests': '$requests'});
    return _parse(() => (data['people'] as List)
        .map((p) => FeedPerson.fromJson(p as Map<String, dynamic>))
        .toList());
  }

  @override
  Future<void> follow(String personId, bool following) async {
    await _request(following ? 'PUT' : 'DELETE',
        '/people/${Uri.encodeComponent(personId)}/follow');
  }

  @override
  Future<void> friendship(String personId, String action) async {
    await _request('PUT', '/people/${Uri.encodeComponent(personId)}/friendship',
        body: {'action': action});
  }

  void close() => _client.close();
}
