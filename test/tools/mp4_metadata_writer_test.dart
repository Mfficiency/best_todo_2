import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:besttodo/services/mp4_metadata_writer.dart';
import 'package:flutter_test/flutter_test.dart';

/// A from-scratch, independent MP4 box reader used only to verify what
/// [Mp4MetadataWriter] produced — it deliberately doesn't share any code
/// with the writer, so a bug in one won't be masked by the same bug in the
/// other.
class _Box {
  _Box(this.type, this.start, this.payloadStart, this.end);
  final String type;
  final int start, payloadStart, end;
}

List<_Box> _readBoxes(Uint8List data, int start, int end) {
  final out = <_Box>[];
  final view = ByteData.sublistView(data);
  var o = start;
  while (o + 8 <= end) {
    final size = view.getUint32(o);
    final type = ascii.decode(data.sublist(o + 4, o + 8));
    if (size < 8 || o + size > end) break;
    out.add(_Box(type, o, o + 8, o + size));
    o += size;
  }
  return out;
}

_Box? _find(List<_Box> boxes, String type) {
  for (final b in boxes) {
    if (b.type == type) return b;
  }
  return null;
}

const _recurseInto = {'moov', 'trak', 'mdia', 'minf', 'stbl', 'udta', 'meta'};

List<_Box> _findAll(Uint8List data, int start, int end, String type) {
  final out = <_Box>[];
  for (final b in _readBoxes(data, start, end)) {
    if (b.type == type) out.add(b);
    if (_recurseInto.contains(b.type)) {
      // `meta`'s payload starts with a 4-byte version/flags field before
      // its children.
      final childStart = b.type == 'meta' ? b.payloadStart + 4 : b.payloadStart;
      out.addAll(_findAll(data, childStart, b.end, type));
    }
  }
  return out;
}

String _fourccAt(Uint8List data, int offset) =>
    String.fromCharCodes(data.sublist(offset, offset + 4));

Map<String, String> _decodeIlst(Uint8List data, _Box ilst) {
  final result = <String, String>{};
  final view = ByteData.sublistView(data);
  var o = ilst.payloadStart;
  while (o + 8 <= ilst.end) {
    final size = view.getUint32(o);
    if (size < 8 || o + size > ilst.end) break;
    final type = _fourccAt(data, o + 4);
    final dataBox = _find(_readBoxes(data, o + 8, o + size), 'data');
    if (dataBox != null) {
      final wellKnown = view.getUint32(dataBox.payloadStart);
      final content = data.sublist(dataBox.payloadStart + 8, dataBox.end);
      result[type] = wellKnown == 13
          ? '<jpeg ${content.length} bytes>'
          : utf8.decode(content, allowMalformed: true);
    }
    o += size;
  }
  return result;
}

Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);

Uint8List _box(String type, List<int> payload) {
  final b = BytesBuilder();
  b.add(_u32(8 + payload.length));
  b.add(ascii.encode(type));
  b.add(payload);
  return b.toBytes();
}

/// A minimal but structurally real MP4/M4A file with one audio track and a
/// two-entry `stco` chunk-offset table pointing at known bytes inside
/// `mdat`, so tagging can be checked against real offsets rather than just
/// "the file got bigger".
class _Synthetic {
  _Synthetic(this.bytes, this.expectedByteAt);
  final Uint8List bytes;
  final List<int> expectedByteAt; // value expected at each chunk's offset
}

_Synthetic _buildSyntheticMp4({required bool moovBeforeMdat}) {
  final ftyp = _box('ftyp', [
    ...ascii.encode('isom'),
    ..._u32(512),
    ...ascii.encode('isomiso2mp41'),
  ]);
  final mdatPayload = Uint8List.fromList(List<int>.generate(64, (i) => i));
  final mdat = _box('mdat', mdatPayload);
  const rel1 = 4;
  const rel2 = 40;

  Uint8List buildStco(int mdatPayloadAbsStart) {
    final payload = BytesBuilder()
      ..add(_u32(0))
      ..add(_u32(2))
      ..add(_u32(mdatPayloadAbsStart + rel1))
      ..add(_u32(mdatPayloadAbsStart + rel2));
    return _box('stco', payload.toBytes());
  }

  Uint8List buildMoov(int mdatPayloadAbsStart) {
    final stbl = _box('stbl', [
      ..._box('stsd', []),
      ..._box('stts', []),
      ..._box('stsc', []),
      ..._box('stsz', []),
      ...buildStco(mdatPayloadAbsStart),
    ]);
    final minf = _box('minf', stbl);
    final mdia = _box('mdia', [
      ..._box('mdhd', List.filled(20, 0)),
      ..._box('hdlr', List.filled(20, 0)),
      ...minf,
    ]);
    final trak = _box('trak', [..._box('tkhd', List.filled(20, 0)), ...mdia]);
    return _box('moov', [..._box('mvhd', List.filled(20, 0)), ...trak]);
  }

  Uint8List fileBytes;
  int mdatAbsStart;
  if (moovBeforeMdat) {
    final probeMoov = buildMoov(0);
    mdatAbsStart = ftyp.length + probeMoov.length + 8;
    final moov = buildMoov(mdatAbsStart);
    fileBytes = Uint8List.fromList([...ftyp, ...moov, ...mdat]);
  } else {
    mdatAbsStart = ftyp.length + 8;
    final moov = buildMoov(mdatAbsStart);
    fileBytes = Uint8List.fromList([...ftyp, ...mdat, ...moov]);
  }

  return _Synthetic(fileBytes, [mdatPayload[rel1], mdatPayload[rel2]]);
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mp4_tag_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> runCase(String label, {required bool moovBeforeMdat}) async {
    final synth = _buildSyntheticMp4(moovBeforeMdat: moovBeforeMdat);
    final path = '${tempDir.path}/track.m4a';
    await File(path).writeAsBytes(synth.bytes);

    final coverArt = Uint8List.fromList(List<int>.generate(20, (i) => 0xFF - i));
    final ok = await Mp4MetadataWriter.tag(
      path,
      title: 'Never Gonna Give You Up',
      artist: 'Rick Astley',
      comment: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      year: 1987,
      coverArtJpeg: coverArt,
    );
    expect(ok, isTrue, reason: '$label: tag() should succeed');

    final out = await File(path).readAsBytes();
    final top = _readBoxes(out, 0, out.length);
    expect(top.last.end, out.length,
        reason: '$label: top-level boxes should account for the whole file');
    final moov = _find(top, 'moov');
    final mdat = _find(top, 'mdat');
    expect(moov, isNotNull, reason: '$label: moov still present');
    expect(mdat, isNotNull, reason: '$label: mdat still present');

    final ilstBoxes = _findAll(out, moov!.payloadStart, moov.end, 'ilst');
    expect(ilstBoxes, hasLength(1), reason: '$label: exactly one ilst atom');
    final tags = _decodeIlst(out, ilstBoxes.first);
    expect(tags['©nam'], 'Never Gonna Give You Up');
    expect(tags['©ART'], 'Rick Astley');
    expect(tags['aART'], 'Rick Astley');
    expect(
        tags['©cmt'], 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    expect(tags['©day'], '1987');
    expect(tags['covr'], '<jpeg 20 bytes>');

    // The real correctness check: every chunk offset in the *rewritten*
    // file must still point at the original audio byte, whether or not it
    // moved.
    final stcoBoxes = _findAll(out, moov.payloadStart, moov.end, 'stco');
    expect(stcoBoxes, hasLength(1));
    final view = ByteData.sublistView(out);
    final entryCount = view.getUint32(stcoBoxes.first.payloadStart + 4);
    expect(entryCount, 2);
    for (var i = 0; i < entryCount; i++) {
      final offset = view.getUint32(stcoBoxes.first.payloadStart + 8 + i * 4);
      expect(out[offset], synth.expectedByteAt[i],
          reason: '$label: chunk $i offset points at the right audio byte');
    }
  }

  group('Mp4MetadataWriter.tag', () {
    test('tags a file where moov comes after mdat (the common layout)',
        () => runCase('moov after mdat', moovBeforeMdat: false));

    test('tags a file where moov comes before mdat, shifting chunk offsets',
        () => runCase('moov before mdat', moovBeforeMdat: true));

    test('a fragmented file (moof present) is left byte-for-byte untouched',
        () async {
      final ftyp = _box('ftyp', ascii.encode('isom'));
      final moov = _box('moov', _box('mvhd', List.filled(20, 0)));
      final moof = _box('moof', _box('mfhd', List.filled(8, 0)));
      final mdat = _box('mdat', List<int>.generate(16, (i) => i));
      final original = Uint8List.fromList([...ftyp, ...moov, ...moof, ...mdat]);
      final path = '${tempDir.path}/fragmented.m4a';
      await File(path).writeAsBytes(original);

      final ok = await Mp4MetadataWriter.tag(path, title: 'X', artist: 'Y');
      expect(ok, isFalse);
      final after = await File(path).readAsBytes();
      expect(after, orderedEquals(original));
    });

    test('a file with no moov is left untouched and reports failure',
        () async {
      final original =
          Uint8List.fromList([..._box('ftyp', ascii.encode('isom')), ..._box('mdat', [1, 2, 3])]);
      final path = '${tempDir.path}/no_moov.m4a';
      await File(path).writeAsBytes(original);

      final ok = await Mp4MetadataWriter.tag(path, title: 'X', artist: 'Y');
      expect(ok, isFalse);
      expect(await File(path).readAsBytes(), orderedEquals(original));
    });

    test('omits absent fields instead of writing empty atoms', () async {
      final synth = _buildSyntheticMp4(moovBeforeMdat: false);
      final path = '${tempDir.path}/minimal.m4a';
      await File(path).writeAsBytes(synth.bytes);

      final ok =
          await Mp4MetadataWriter.tag(path, title: 'Only Title', artist: '');
      expect(ok, isTrue);

      final out = await File(path).readAsBytes();
      final moov = _find(_readBoxes(out, 0, out.length), 'moov')!;
      final ilst = _findAll(out, moov.payloadStart, moov.end, 'ilst').first;
      final tags = _decodeIlst(out, ilst);
      expect(tags['©nam'], 'Only Title');
      expect(tags.containsKey('©ART'), isFalse);
      expect(tags.containsKey('aART'), isFalse);
      expect(tags.containsKey('©cmt'), isFalse);
      expect(tags.containsKey('©day'), isFalse);
      expect(tags.containsKey('covr'), isFalse);
    });
  });
}
