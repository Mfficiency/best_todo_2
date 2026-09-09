import 'dart:convert';

import 'package:besttodo/services/github_wishlist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('GithubWishlistService', () {
    test('createWishlistIssue posts title/body/label with a bearer token',
        () async {
      http.Request? captured;
      final service = GithubWishlistService(
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'html_url':
                  'https://github.com/Mfficiency/best_todo_2/issues/7',
            }),
            201,
          );
        }),
      );

      final url = await service.createWishlistIssue(
        token: 'secret-token',
        title: 'Learn to sail',
        body: 'Build the following items from my BestToDo wishlist:',
      );

      expect(captured!.method, 'POST');
      expect(captured!.headers['Authorization'], 'Bearer secret-token');
      expect(
        captured!.url.toString(),
        'https://api.github.com/repos/${GithubWishlistService.owner}/'
        '${GithubWishlistService.repo}/issues',
      );
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['title'], 'Learn to sail');
      expect(body['body'],
          'Build the following items from my BestToDo wishlist:');
      expect(body['labels'], [GithubWishlistService.buildLabel]);
      expect(url, 'https://github.com/Mfficiency/best_todo_2/issues/7');
    });

    test('a non-2xx response throws GithubApiException with the status code',
        () async {
      final service = GithubWishlistService(
        client:
            MockClient((request) async => http.Response('Bad creds', 401)),
      );

      expect(
        () => service.createWishlistIssue(
          token: 'bad-token',
          title: 'x',
          body: 'y',
        ),
        throwsA(isA<GithubApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('testConnection succeeds on a 2xx repo response', () async {
      final service = GithubWishlistService(
        client: MockClient((request) async => http.Response('{}', 200)),
      );

      await service.testConnection('a-token');
    });

    test('testConnection throws on a 404 (token can\'t see the repo)',
        () async {
      final service = GithubWishlistService(
        client: MockClient((request) async => http.Response('Not Found', 404)),
      );

      expect(
        () => service.testConnection('a-token'),
        throwsA(isA<GithubApiException>()
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });
}
