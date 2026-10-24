import 'dart:convert';
import 'package:connectly/features/feed/data/feed_api.dart';
import 'package:connectly/features/feed/domain/feed_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('feed requests carry the current session, filter, and encoded cursor',
      () async {
    var token = 'first-session';
    final api = FeedApi(
        token: () => token,
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer second-session');
          expect(request.url.queryParameters['scope'], 'friends');
          expect(request.url.queryParameters['cursor'], 'time|id');
          return http.Response('{"posts":[],"nextCursor":null}', 200);
        }));
    token = 'second-session';
    expect(
        (await api.load(scope: 'friends', cursor: 'time|id')).posts, isEmpty);
    api.close();
  });

  test('guests cannot send feed requests', () async {
    final api = FeedApi(
        token: () => null,
        client:
            MockClient((_) async => throw StateError('Unexpected request')));
    await expectLater(
        api.load(scope: 'connections'),
        throwsA(
            isA<FeedException>().having((e) => e.statusCode, 'status', 401)));
    api.close();
  });

  test('reaction replacement/removal uses PUT/DELETE and no client count',
      () async {
    var calls = 0;
    final api = FeedApi(
        token: () => 'session',
        client: MockClient((request) async {
          calls++;
          expect(request.url.path, '/posts/post-1/reaction');
          expect(request.method, calls == 1 ? 'PUT' : 'DELETE');
          if (calls == 1) {
            expect(jsonDecode(request.body), {'kind': 'love'});
          } else {
            expect(request.body, isEmpty);
          }
          return http.Response(
              jsonEncode({
                'post': {
                  'id': 'post-1',
                  'author': {'id': 'a', 'name': 'Author'},
                  'body': 'Hello',
                  'createdAt': '2026-10-24T00:00:00Z',
                  'reactions': {'love': calls == 1 ? 1 : 0},
                  'myReaction': calls == 1 ? 'love' : null
                }
              }),
              200);
        }));
    expect((await api.react('post-1', 'love')).reactionCount, 1);
    expect((await api.react('post-1', null)).myReaction, isNull);
    api.close();
  });

  test('service failures preserve safe error messages', () async {
    final api = FeedApi(
        token: () => 'session',
        client: MockClient((_) async =>
            http.Response('{"error":{"message":"Post unavailable"}}', 404)));
    await expectLater(
        api.react('deleted', 'like'),
        throwsA(isA<FeedException>()
            .having((e) => e.message, 'message', 'Post unavailable')));
    api.close();
  });
}
