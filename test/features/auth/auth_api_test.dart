import 'dart:convert';

import 'package:connectly/features/auth/data/auth_api.dart';
import 'package:connectly/features/auth/domain/auth_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
      'sends login credentials only to the auth endpoint and parses the session',
      () async {
    final api = AuthApi(client: MockClient((request) async {
      expect(request.url.path, '/auth/login');
      expect(request.method, 'POST');
      expect(request.headers['authorization'], isNull);
      expect(jsonDecode(request.body),
          {'email': 'member@example.com', 'password': ' exact password '});
      return http.Response(
          jsonEncode({
            'token': 'user-session',
            'user': {
              'id': '1',
              'name': 'Member',
              'email': 'member@example.com',
              'createdAt': '2026-10-24T00:00:00Z'
            },
          }),
          200);
    }));
    final session = await api.signIn('member@example.com', ' exact password ');
    expect(session.user.name, 'Member');
    expect(session.token, 'user-session');
    api.close();
  });

  test('preserves backend authentication errors for display', () async {
    final api = AuthApi(
        client: MockClient((_) async => http.Response(
              '{"error":{"code":"invalid_credentials","message":"Email or password is incorrect."}}',
              401,
            )));
    await expectLater(
        api.signIn('member@example.com', 'wrong'),
        throwsA(
          isA<AuthException>()
              .having((error) => error.statusCode, 'status', 401)
              .having((error) => error.message, 'message',
                  'Email or password is incorrect.'),
        ));
    api.close();
  });

  test('restores profile using the user bearer token', () async {
    final api = AuthApi(client: MockClient((request) async {
      expect(request.url.path, '/me');
      expect(request.headers['authorization'], 'Bearer user-session');
      return http.Response(
          '{"user":{"id":"1","name":"Member","email":"member@example.com","createdAt":"2026-10-24T00:00:00Z"}}',
          200);
    }));
    expect((await api.currentUser('user-session')).id, '1');
    api.close();
  });
}
