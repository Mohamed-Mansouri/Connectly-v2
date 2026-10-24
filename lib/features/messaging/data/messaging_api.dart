import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../domain/messaging_models.dart';

class MessagingApi implements MessagingRepository {
  MessagingApi(
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
      {Map<String, Object>? body, Map<String, String>? query}) async {
    final token = _token();
    if (token == null) {
      throw const MessagingException('Sign in to use messages.',
          statusCode: 401);
    }
    try {
      final request = http.Request(
          method, _baseUri.resolve(path).replace(queryParameters: query));
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
        throw MessagingException(
            (data['error'] as Map<String, dynamic>?)?['message'] as String? ??
                'Could not complete the request. Please try again.',
            statusCode: response.statusCode);
      }
      return data;
    } on TimeoutException {
      throw const MessagingException(
          'The connection timed out. Please try again.');
    } on http.ClientException {
      throw const MessagingException(
          'Could not connect. Check your connection and try again.');
    } on FormatException {
      throw const MessagingException(
          'Could not read the service response. Please try again.');
    } on TypeError {
      throw const MessagingException(
          'Could not read the service response. Please try again.');
    }
  }

  T _parse<T>(T Function() parse) {
    try {
      return parse();
    } on Object {
      throw const MessagingException(
          'Could not read the service response. Please try again.');
    }
  }

  String _path(String id) => '/conversations/${Uri.encodeComponent(id)}';
  @override
  Future<List<Conversation>> conversations() async {
    final data = await _request('GET', '/conversations');
    return _parse(() => (data['conversations'] as List)
        .map((c) => Conversation.fromJson(c as Map<String, dynamic>))
        .toList());
  }

  @override
  Future<List<ChatPerson>> contacts(String search) async {
    final data = await _request('GET', '/conversations/contacts',
        query: {'search': search.trim()});
    return _parse(() => (data['contacts'] as List)
        .map((c) => ChatPerson.fromJson(c as Map<String, dynamic>))
        .toList());
  }

  @override
  Future<Conversation> create(
      {required String kind,
      required List<String> memberIds,
      String? title}) async {
    final data = await _request('POST', '/conversations', body: {
      'kind': kind,
      'memberIds': memberIds,
      if (title != null) 'title': title.trim()
    });
    return _parse(() =>
        Conversation.fromJson(data['conversation'] as Map<String, dynamic>));
  }

  @override
  Future<List<ChatPerson>> members(String conversationId) async {
    final data = await _request('GET', '${_path(conversationId)}/members');
    return _parse(() => (data['members'] as List)
        .map((c) => ChatPerson.fromJson(c as Map<String, dynamic>))
        .toList());
  }

  @override
  Future<MessagePage> messages(String conversationId,
      {int? before, int? after}) async {
    final data = await _request('GET', '${_path(conversationId)}/messages',
        query: {
          if (before != null) 'before': '$before',
          if (after != null) 'after': '$after'
        });
    return _parse(() => MessagePage(
        (data['messages'] as List)
            .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
            .toList(),
        olderCursor: data['olderCursor'] as int?,
        hasMore: data['hasMore'] as bool));
  }

  @override
  Future<ChatMessage> send(
      String conversationId, String clientId, String body) async {
    final data = await _request('POST', '${_path(conversationId)}/messages',
        body: {'clientId': clientId, 'body': body});
    return _parse(
        () => ChatMessage.fromJson(data['message'] as Map<String, dynamic>));
  }

  @override
  Future<void> markRead(String conversationId, int throughSequence) async {
    await _request('POST', '${_path(conversationId)}/read',
        body: {'throughSequence': throughSequence});
  }

  void close() => _client.close();
}
