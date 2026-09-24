import 'package:besttodo/services/music_player_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ensurePermissions is a no-op off Android (tests run on host)',
      () async {
    // Just needs to complete without throwing — the permission_handler
    // plugin channel isn't available on the host platform tests run on.
    await MusicPlayerService.ensurePermissions();
    await MusicPlayerService.ensurePermissions(eager: true);
  });
}
