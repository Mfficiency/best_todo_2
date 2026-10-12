/// Checks a vendored copy of this package (`<app>/packages/mfficiency_updates`)
/// against the hashes its ORIGIN file records, so hand edits in an app fail
/// its tests. dart:io only: import it from tests, not from the app.
library;

import 'dart:io';
import 'dart:typed_data';

/// Files and folders that tools create inside a package; never vendored.
bool _ignored(String path) {
  final parts = path.split('/');
  return parts.any(
        (p) =>
            p == '.dart_tool' ||
            p == 'build' ||
            p == '.gradle' ||
            p == '.idea' ||
            p == '.cxx',
      ) ||
      path == 'ORIGIN' ||
      path == 'pubspec.lock' ||
      path == 'android/local.properties' ||
      path.startsWith('.flutter-plugins') ||
      path.endsWith('.iml') ||
      parts.last == '.DS_Store';
}

/// What is wrong with the vendored copy in [dir] (empty: it matches its
/// ORIGIN): a file changed, missing or added by hand.
List<String> vendoredCopyProblems(Directory dir) {
  final origin = File('${dir.path}/ORIGIN');
  if (!origin.existsSync()) return ['${origin.path} is missing'];
  final expected = <String, String>{};
  for (final line in origin.readAsLinesSync()) {
    final m = RegExp(r'^([0-9a-f]{64})  (.+)$').firstMatch(line.trim());
    if (m != null) expected[m.group(2)!] = m.group(1)!;
  }
  if (expected.isEmpty) return ['${origin.path} lists no files'];
  final problems = <String>[];
  final root = dir.absolute.path.replaceAll(r'\', '/');
  final seen = <String>{};
  for (final f in dir.listSync(recursive: true).whereType<File>()) {
    final path = f.absolute.path
        .replaceAll(r'\', '/')
        .substring(root.length)
        .replaceFirst(RegExp('^/'), '');
    if (_ignored(path)) continue;
    seen.add(path);
    final want = expected[path];
    if (want == null) {
      problems.add('$path: not in the template (added by hand?)');
    } else if (fileHash(f.readAsBytesSync()) != want) {
      problems.add('$path: changed by hand');
    }
  }
  for (final path in expected.keys) {
    if (!seen.contains(path)) problems.add('$path: missing');
  }
  return problems..sort();
}

/// The hash ORIGIN records: SHA-256 (hex) of the file with every CR byte
/// removed, so a checkout with CRLF line endings (Windows) matches too.
String fileHash(List<int> bytes) =>
    sha256Hex(bytes.where((b) => b != 13).toList());

/// SHA-256 of [data] as lowercase hex (FIPS 180-4; no package needed).
String sha256Hex(List<int> data) {
  const k = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];
  final h = <int>[
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];
  const mask = 0xffffffff;
  int rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & mask;

  final bitLength = data.length * 8;
  final padded = BytesBuilder(copy: false)
    ..add(data)
    ..addByte(0x80);
  var length = data.length + 1;
  while (length % 64 != 56) {
    padded.addByte(0);
    length++;
  }
  final lengthBytes = ByteData(8)
    ..setUint32(0, (bitLength ~/ 0x100000000) & mask)
    ..setUint32(4, bitLength & mask);
  padded.add(lengthBytes.buffer.asUint8List());
  final bytes = ByteData.sublistView(padded.takeBytes());

  final w = List<int>.filled(64, 0);
  for (var chunk = 0; chunk < bytes.lengthInBytes; chunk += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = bytes.getUint32(chunk + i * 4);
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & mask;
    }
    var a = h[0], b = h[1], c = h[2], d = h[3];
    var e = h[4], f = h[5], g = h[6], hh = h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final ch = (e & f) ^ ((~e & mask) & g);
      final t1 = (hh + s1 + ch + k[i] + w[i]) & mask;
      final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & mask;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & mask;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & mask;
    }
    h[0] = (h[0] + a) & mask;
    h[1] = (h[1] + b) & mask;
    h[2] = (h[2] + c) & mask;
    h[3] = (h[3] + d) & mask;
    h[4] = (h[4] + e) & mask;
    h[5] = (h[5] + f) & mask;
    h[6] = (h[6] + g) & mask;
    h[7] = (h[7] + hh) & mask;
  }
  return h.map((x) => x.toRadixString(16).padLeft(8, '0')).join();
}
