import 'package:shared_preferences/shared_preferences.dart';

/// Where the update state lives (last check, downloaded build, install
/// time). Small key/value pairs, read synchronously after start.
abstract class UpdateStore {
  String? getString(String key);
  int? getInt(String key);
  Future<void> setString(String key, String value);
  Future<void> setInt(String key, int value);
}

/// [UpdateStore] on the app's SharedPreferences (every app has them).
class SharedPreferencesUpdateStore implements UpdateStore {
  SharedPreferencesUpdateStore(this.prefs);
  final SharedPreferences prefs;

  @override
  String? getString(String key) => prefs.getString(key);

  @override
  int? getInt(String key) => prefs.getInt(key);

  @override
  Future<void> setString(String key, String value) =>
      prefs.setString(key, value);

  @override
  Future<void> setInt(String key, int value) => prefs.setInt(key, value);
}

/// [UpdateStore] in memory (tests).
class MemoryUpdateStore implements UpdateStore {
  MemoryUpdateStore([Map<String, Object>? values]) : values = {...?values};
  final Map<String, Object> values;

  @override
  String? getString(String key) => values[key] as String?;

  @override
  int? getInt(String key) => values[key] as int?;

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<void> setInt(String key, int value) async => values[key] = value;
}
