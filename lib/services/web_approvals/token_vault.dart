import 'dart:convert';
import 'dart:typed_data';

import 'vault_crypto.dart';

/// Where [TokenVault] keeps its few strings (the browser's localStorage on
/// the site, via SharedPreferences; a map in tests).
abstract class VaultStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class WrongPasswordException implements Exception {
  const WrongPasswordException();
  @override
  String toString() => 'Wrong password';
}

/// Thrown by [TokenVault.unlock] when there's no vault (and no ban): the
/// token has to be entered again.
class VaultWipedException implements Exception {
  const VaultWipedException();
  @override
  String toString() => 'Vault wiped';
}

/// The approvals site's only stored secret: the Todoist API token, encrypted
/// with a key derived from a password the person chooses (SPEC §4.2k). The
/// browser never holds the token in the clear between visits — a copy of
/// localStorage is useless without the password, and every guess costs a
/// full PBKDF2 run.
///
/// [maxAttempts] wrong passwords in a row shadow-ban the browser: the vault
/// is deleted at once and, for [banDuration], every attempt — the right
/// password included — just answers "wrong password" after a realistic
/// delay, and the vault can't be set up again. Nothing on screen says so.
class TokenVault {
  static const vaultKey = 'web_approvals_vault';
  static const failuresKey = 'web_approvals_failures';
  // Deliberately bland: it's the ban's end time.
  static const bannedUntilKey = 'web_approvals_state';

  /// OWASP's 2023 recommendation for PBKDF2-HMAC-SHA256.
  static const int defaultIterations = 600000;
  static const int minPasswordLength = 12;
  static const int maxAttempts = 2;
  static const Duration banDuration = Duration(days: 90);

  /// How long a banned attempt pretends to work (a real one runs PBKDF2).
  static const Duration fakeCheckTime = Duration(milliseconds: 1200);

  final VaultStore store;
  final VaultCrypto crypto;
  final int iterations;
  final DateTime Function() now;
  final Future<void> Function(Duration) delay;

  TokenVault({
    required this.store,
    required this.crypto,
    this.iterations = defaultIterations,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  })  : now = now ?? DateTime.now,
        delay = delay ?? Future<void>.delayed;

  Future<bool> exists() async => (await store.read(vaultKey)) != null;

  /// Whether the browser is shadow-banned (see the class doc).
  Future<bool> isBanned() async {
    final until = int.tryParse(await store.read(bannedUntilKey) ?? '');
    if (until == null) return false;
    if (now().isBefore(DateTime.fromMillisecondsSinceEpoch(until))) return true;
    await store.delete(bannedUntilKey);
    return false;
  }

  /// Null when the password is acceptable, else the reason it isn't.
  static String? passwordProblem(String password) {
    if (password.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters';
    }
    return null;
  }

  /// Encrypts [token] under [password], replacing any existing vault.
  Future<void> create(String token, String password) async {
    if (await isBanned()) throw StateError('Not available');
    final problem = passwordProblem(password);
    if (problem != null) throw ArgumentError(problem);
    final salt = crypto.randomBytes(16);
    final iv = crypto.randomBytes(12);
    final ciphertext = await crypto.encrypt(
      password: password,
      salt: salt,
      iterations: iterations,
      iv: iv,
      plaintext: Uint8List.fromList(utf8.encode(token)),
    );
    await store.write(
      vaultKey,
      jsonEncode({
        'v': 1,
        'kdf': 'PBKDF2-SHA256',
        'iterations': iterations,
        'salt': base64Encode(salt),
        'iv': base64Encode(iv),
        'ciphertext': base64Encode(ciphertext),
      }),
    );
    await _resetFailures();
  }

  /// The decrypted token. Throws [WrongPasswordException] for a wrong
  /// password — and for every attempt while banned — and
  /// [VaultWipedException] when there is no vault to open.
  Future<String> unlock(String password) async {
    if (await isBanned()) {
      await delay(fakeCheckTime);
      throw const WrongPasswordException();
    }
    final raw = await store.read(vaultKey);
    if (raw == null) throw const VaultWipedException();
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      await forget();
      throw const VaultWipedException();
    }
    try {
      final plain = await crypto.decrypt(
        password: password,
        salt: base64Decode(data['salt'] as String),
        iterations: data['iterations'] as int,
        iv: base64Decode(data['iv'] as String),
        ciphertext: base64Decode(data['ciphertext'] as String),
      );
      await _resetFailures();
      return utf8.decode(plain);
    } catch (_) {
      final failures =
          (int.tryParse(await store.read(failuresKey) ?? '') ?? 0) + 1;
      if (failures >= maxAttempts) {
        await forget();
        await store.write(bannedUntilKey,
            '${now().add(banDuration).millisecondsSinceEpoch}');
      } else {
        await store.write(failuresKey, '$failures');
      }
      throw const WrongPasswordException();
    }
  }

  Future<void> _resetFailures() => store.delete(failuresKey);

  /// Deletes the vault and its counter ("Forget this browser"). A ban stays.
  Future<void> forget() async {
    await store.delete(vaultKey);
    await _resetFailures();
  }
}
