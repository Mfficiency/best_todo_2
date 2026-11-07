import 'dart:typed_data';

import 'vault_crypto_stub.dart'
    if (dart.library.js_interop) 'vault_crypto_web.dart' as impl;

/// The password-based encryption behind [TokenVault]: PBKDF2-SHA256 derives
/// an AES-256-GCM key from the password and a random salt. On the web it is
/// the browser's own Web Crypto (`crypto.subtle`, never a Dart port); other
/// platforms have no implementation — the approvals site only runs in a
/// browser — and tests pass a fake.
abstract class VaultCrypto {
  static VaultCrypto get platform => impl.platformCrypto();

  /// [length] cryptographically random bytes (salts, IVs).
  Uint8List randomBytes(int length);

  /// AES-GCM-encrypts [plaintext] under the key derived from [password].
  Future<Uint8List> encrypt({
    required String password,
    required Uint8List salt,
    required int iterations,
    required Uint8List iv,
    required Uint8List plaintext,
  });

  /// Reverses [encrypt]. Throws when the password is wrong (GCM's tag check
  /// fails) or the data was tampered with — the two are indistinguishable.
  Future<Uint8List> decrypt({
    required String password,
    required Uint8List salt,
    required int iterations,
    required Uint8List iv,
    required Uint8List ciphertext,
  });
}
