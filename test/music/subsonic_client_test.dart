import 'package:besttodo/config.dart';
import 'package:besttodo/services/subsonic_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    Config.subsonicServerUrl = '';
    Config.subsonicUsername = '';
    Config.subsonicPassword = '';
  });

  tearDown(() {
    Config.subsonicServerUrl = '';
    Config.subsonicUsername = '';
    Config.subsonicPassword = '';
  });

  test('isConfigured requires both a server URL and a username', () {
    expect(SubsonicClient.instance.isConfigured, isFalse);

    Config.subsonicServerUrl = 'https://music.example.com';
    expect(SubsonicClient.instance.isConfigured, isFalse);

    Config.subsonicUsername = 'me';
    expect(SubsonicClient.instance.isConfigured, isTrue);
  });

  test('streamUri builds a /rest/stream URL carrying the song id and auth '
      'params, with a trailing slash on the server URL stripped', () {
    Config.subsonicServerUrl = 'https://music.example.com/';
    Config.subsonicUsername = 'me';
    Config.subsonicPassword = 'secret';

    final uri = SubsonicClient.instance.streamUri('song-42');

    expect(uri.scheme, 'https');
    expect(uri.host, 'music.example.com');
    expect(uri.path, '/rest/stream');
    expect(uri.queryParameters['id'], 'song-42');
    expect(uri.queryParameters['u'], 'me');
    expect(uri.queryParameters['v'], SubsonicClient.apiVersion);
    expect(uri.queryParameters['c'], SubsonicClient.clientName);
    expect(uri.queryParameters['f'], 'json');
    // The password itself must never appear in the URL — only a salted
    // token does.
    expect(uri.toString(), isNot(contains('secret')));
    expect(uri.queryParameters['t'], isNotEmpty);
    expect(uri.queryParameters['s'], isNotEmpty);
  });

  test('two calls use a different salt/token (never reuse one)', () {
    Config.subsonicServerUrl = 'https://music.example.com';
    Config.subsonicUsername = 'me';
    Config.subsonicPassword = 'secret';

    final first = SubsonicClient.instance.streamUri('song-1');
    final second = SubsonicClient.instance.streamUri('song-1');

    expect(first.queryParameters['s'], isNot(second.queryParameters['s']));
  });

  test('ping()/search() fail closed (false/empty) when not configured',
      () async {
    expect(await SubsonicClient.instance.ping(), isFalse);
    expect(await SubsonicClient.instance.search('anything'), isEmpty);
  });
}
