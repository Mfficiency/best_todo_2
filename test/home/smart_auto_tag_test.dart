import 'dart:convert';

import 'package:besttodo/config.dart';
import 'package:besttodo/services/auto_tag_service.dart';
import 'package:besttodo/services/jev_decision_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<http.Request> requests;

  void mockJev(String choice, double confidence, {int status = 200}) {
    JevDecisionService.instance = JevDecisionService(
      client: MockClient((request) async {
        requests.add(request);
        if (status != 200) return http.Response('nope', status);
        return http.Response(
          jsonEncode({
            'model': 'jev-1.13.0',
            'answers': {
              'pick': {
                'type': 'choice',
                'choice': choice,
                'confidence': confidence,
              },
            },
            'usage': {'input_tokens': 120, 'output_tokens': 4},
          }),
          200,
        );
      }),
    );
  }

  setUp(() {
    requests = [];
    AutoTagService.instance.resetForTest();
    Config.autoTagEnabled = true;
    Config.smartAutoTagEnabled = true;
    Config.jevApiKey = 'test-key';
  });

  tearDown(() {
    JevDecisionService.instance = JevDecisionService();
    Config.smartAutoTagEnabled = false;
    Config.jevApiKey = '';
  });

  test('sends one choice question over the tag groups and applies the pick',
      () async {
    mockJev('finance', 0.9);
    final tag = await AutoTagService.instance.smartTagFor('renew my licence');
    expect(tag, 'finance');
    expect(requests, hasLength(1));
    final request = requests.single;
    expect(request.url.toString(), JevDecisionService.endpoint);
    expect(request.headers['Authorization'], 'Bearer test-key');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['model'], 'jev-latest');
    expect(body['state'], 'renew my licence');
    final question = body['questions']['pick'] as Map<String, dynamic>;
    expect(question['type'], 'choice');
    final criteria = question['criteria'] as Map<String, dynamic>;
    expect(criteria.keys, containsAll(['work', 'finance', 'travel']));
    expect(criteria.keys, contains(AutoTagService.noTagOption));
  });

  test('skips the network when the keyword rules already matched', () async {
    mockJev('finance', 0.9);
    expect(await AutoTagService.instance.smartTagFor('go to the gym'), isNull);
    expect(requests, isEmpty);
  });

  test('does nothing when disabled or without an API key', () async {
    mockJev('finance', 0.9);
    Config.smartAutoTagEnabled = false;
    expect(await AutoTagService.instance.smartTagFor('renew licence'), isNull);
    Config.smartAutoTagEnabled = true;
    Config.jevApiKey = '  ';
    expect(await AutoTagService.instance.smartTagFor('renew licence'), isNull);
    expect(requests, isEmpty);
  });

  test('ignores low-confidence, "none" and unknown picks', () async {
    mockJev('finance', 0.4);
    expect(await AutoTagService.instance.smartTagFor('renew licence'), isNull);
    mockJev(AutoTagService.noTagOption, 0.99);
    expect(await AutoTagService.instance.smartTagFor('renew licence'), isNull);
    mockJev('made-up-tag', 0.99);
    expect(await AutoTagService.instance.smartTagFor('renew licence'), isNull);
  });

  test('swallows API errors', () async {
    mockJev('finance', 0.9, status: 429);
    expect(await AutoTagService.instance.smartTagFor('renew licence'), isNull);
    expect(requests, hasLength(1));
  });
}
