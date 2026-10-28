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
  /// Attempts left before the vault wipes itself.
  final int attemptsLeft;
  const WrongPasswordException(this.attemptsLeft);
  @override
  String toString() => 'Wrong password';
}

class VaultLockedOutException implements Exception {
  final Duration retryIn;
  const VaultLockedOutException(this.retryIn);
  @override
  String toString() => 'Too many attempts';
}

/// Thrown by [TokenVault.unlock] when the last allowed attempt failed: the
/// vault is gone, the token has to be entered again.
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
/// Wrong passwords are throttled: from the [freeAttempts]th failure on, each
/// further try waits twice as long as the last (capped at [maxDelay]), and
/// [maxAttempts] failures in a row delete the vault.
class TokenVault {
  static const vaultKey = 'web_approvals_vault';
  static const failuresKey = 'web_approvals_failures';
  static const lockedUntilKey = 'web_approvals_locked_until';

  /// OWASP's 2023 recommendation for PBKDF2-HMAC-SHA256.
  static const int defaultIterations = 600000;
  static const int minPasswordLength = 12;
  static const int freeAttempts = 3;
  static const int maxAttempts = 10;
  static const Duration maxDelay = Duration(minutes: 5);

  final VaultStore store;
  final VaultCrypto crypto;
  final int iterations;
  final DateTime Function() now;

  TokenVault({
    required this.store,
    required this.crypto,
    this.iterations = defaultIterations,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  Future<bool> exists() async => (await store.read(vaultKey)) != null;

  /// Null when the password is acceptable, else the reason it isn't.
  static String? passwordProblem(String password) {
    if (password.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters';
    }
    return null;
  }

  /// Encrypts [token] under [password], replacing any existing vault.
  Future<void> create(String token, String password) async {
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

  /// How long until the next attempt is allowed (zero = now).
  Future<Duration> lockedFor() async {
    final until = int.tryParse(await store.read(lockedUntilKey) ?? '');
    if (until == null) return Duration.zero;
    final left = DateTime.fromMillisecondsSinceEpoch(until).difference(now());
    return left.isNegative ? Duration.zero : left;
  }

  /// The decrypted token. Throws [VaultLockedOutException] while throttled,
  /// [WrongPasswordException] for a wrong password and [VaultWipedException]
  /// when that was the last allowed attempt.
  Future<String> unlock(String password) async {
    final raw = await store.read(vaultKey);
    if (raw == null) throw const VaultWipedException();
    final wait = await lockedFor();
    if (wait > Duration.zero) throw VaultLockedOutException(wait);
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
        throw const VaultWipedException();
      }
      await store.write(failuresKey, '$failures');
      if (failures >= freeAttempts) {
        final delay = _delayAfter(failures);
        await store.write(lockedUntilKey,
            '${now().add(delay).millisecondsSinceEpoch}');
      }
      throw WrongPasswordException(maxAttempts - failures);
    }
  }

  /// 3rd failure → 5 s, then 10 s, 20 s, … up to [maxDelay].
  static Duration _delayAfter(int failures) {
    final seconds = 5 * (1 << (failures - freeAttempts));
    final delay = Duration(seconds: seconds);
    return delay > maxDelay ? maxDelay : delay;
  }

  Future<void> _resetFailures() async {
    await store.delete(failuresKey);
    await store.delete(lockedUntilKey);
  }

  /// Deletes the vault and its counters ("Forget this browser").
  Future<void> forget() async {
    await store.delete(vaultKey);
    await _resetFailures();
  }
}
