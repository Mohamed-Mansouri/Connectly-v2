import 'dart:convert';
import 'package:connectly/features/messaging/data/messaging_api.dart';
import 'package:connectly/features/messaging/domain/messaging_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('send uses the current bearer token and preserves the supplied retry ID',
      () async {
    final api = MessagingApi(
        token: () => 'session',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/conversations/chat-1/messages');
          expect(request.headers['Authorization'], 'Bearer session');
          expect(jsonDecode(request.body),
              {'clientId': 'stable-id', 'body': 'Hello'});
          return http.Response(
              jsonEncode({
                'message': {
                  'sequence': 1,
                  'clientId': 'stable-id',
                  'sender': {'id': 'me', 'name': 'Member'},
                  'body': 'Hello',
                  'createdAt': '2026-10-24T12:00:00Z'
                }
              }),
              201);
        }));
    expect((await api.send('chat-1', 'stable-id', 'Hello')).sequence, 1);
    api.close();
  });
  test('history sends distinct older and incremental cursors', () async {
    var calls = 0;
    final api = MessagingApi(
        token: () => 'session',
        client: MockClient((request) async {
          expect(request.url.queryParameters,
              calls++ == 0 ? {'before': '50'} : {'after': '75'});
          return http.Response(
              '{"messages":[],"olderCursor":null,"hasMore":false}', 200);
        }));
    await api.messages('chat-1', before: 50);
    await api.messages('chat-1', after: 75);
    api.close();
  });
  test('guest requests are rejected locally', () async {
    final api = MessagingApi(
        token: () => null,
        client:
            MockClient((_) async => throw StateError('Unexpected request')));
    await expectLater(
        api.conversations(),
        throwsA(isA<MessagingException>()
            .having((e) => e.statusCode, 'status', 401)));
    api.close();
  });
  test('membership failures keep the safe server message', () async {
    final api = MessagingApi(
        token: () => 'session',
        client: MockClient((_) async => http.Response(
            '{"error":{"message":"Conversation unavailable"}}', 404)));
    await expectLater(
        api.messages('private'),
        throwsA(isA<MessagingException>()
            .having((e) => e.message, 'message', 'Conversation unavailable')));
    api.close();
  });
}
