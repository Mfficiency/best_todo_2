// @dart=3.3
// (Newer than the package's 3.0 default: extension types for JS interop.)
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'vault_crypto.dart';

VaultCrypto platformCrypto() => _WebCrypto();

@JS('crypto')
external _Crypto get _crypto;

extension type _Crypto._(JSObject _) implements JSObject {
  external _Subtle get subtle;
  external JSUint8Array getRandomValues(JSUint8Array array);
}

extension type _Subtle._(JSObject _) implements JSObject {
  external JSPromise<JSObject> importKey(String format, JSUint8Array keyData,
      JSString algorithm, bool extractable, JSArray<JSString> usages);
  external JSPromise<JSObject> deriveKey(JSObject algorithm, JSObject baseKey,
      JSObject derivedKeyType, bool extractable, JSArray<JSString> usages);
  external JSPromise<JSArrayBuffer> encrypt(
      JSObject algorithm, JSObject key, JSUint8Array data);
  external JSPromise<JSArrayBuffer> decrypt(
      JSObject algorithm, JSObject key, JSUint8Array data);
}

JSObject _object(Map<String, JSAny> fields) {
  final object = JSObject();
  fields.forEach((key, value) => object.setProperty(key.toJS, value));
  return object;
}

class _WebCrypto implements VaultCrypto {
  @override
  Uint8List randomBytes(int length) =>
      _crypto.getRandomValues(Uint8List(length).toJS).toDart;

  /// A non-extractable AES-GCM key: the derived key never exists as bytes
  /// the page could read back.
  Future<JSObject> _key(String password, Uint8List salt, int iterations,
      String usage) async {
    final subtle = _crypto.subtle;
    final material = await subtle
        .importKey(
          'raw',
          Uint8List.fromList(_utf8(password)).toJS,
          'PBKDF2'.toJS,
          false,
          ['deriveKey'.toJS].toJS,
        )
        .toDart;
    return subtle
        .deriveKey(
          _object({
            'name': 'PBKDF2'.toJS,
            'salt': salt.toJS,
            'iterations': iterations.toJS,
            'hash': 'SHA-256'.toJS,
          }),
          material,
          _object({'name': 'AES-GCM'.toJS, 'length': 256.toJS}),
          false,
          [usage.toJS].toJS,
        )
        .toDart;
  }

  @override
  Future<Uint8List> encrypt({
    required String password,
    required Uint8List salt,
    required int iterations,
    required Uint8List iv,
    required Uint8List plaintext,
  }) async {
    final key = await _key(password, salt, iterations, 'encrypt');
    final out = await _crypto.subtle
        .encrypt(_object({'name': 'AES-GCM'.toJS, 'iv': iv.toJS}), key,
            plaintext.toJS)
        .toDart;
    return out.toDart.asUint8List();
  }

  @override
  Future<Uint8List> decrypt({
    required String password,
    required Uint8List salt,
    required int iterations,
    required Uint8List iv,
    required Uint8List ciphertext,
  }) async {
    final key = await _key(password, salt, iterations, 'decrypt');
    final out = await _crypto.subtle
        .decrypt(_object({'name': 'AES-GCM'.toJS, 'iv': iv.toJS}), key,
            ciphertext.toJS)
        .toDart;
    return out.toDart.asUint8List();
  }
}

List<int> _utf8(String s) => const Utf8Codec().encode(s);
