import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Writes iTunes-style metadata atoms (title/artist/comment/year/cover art)
/// into an already-downloaded `.m4a` (MP4 audio) file, without touching the
/// audio itself.
///
/// This does box-level surgery on the MP4 container rather than
/// transcoding: it locates (or creates) `moov/udta/meta/ilst` and splices
/// the new metadata atom in, patching the `stco`/`co64` chunk-offset tables
/// if the size change shifts where the audio data (`mdat`) sits in the
/// file. That is how MP4 tag editors normally work, and it is the only way
/// to add real metadata here without bundling a native
/// encoder/decoder — `ffmpeg_kit_flutter_new_full` was tried for exactly
/// this and dropped for adding 100+ MB to the APK (see
/// [Mp3DownloaderService]'s doc comment).
///
/// Deliberately conservative: anything about the file that doesn't match
/// the simple, single-`mdat`, non-fragmented layout every stream downloaded
/// by this app actually has bails out and leaves the file untouched rather
/// than risk producing a corrupt track. The original file is never
/// modified in place — a tagged copy is built, sanity-checked, and only
/// then renamed over the original.
class Mp4MetadataWriter {
  const Mp4MetadataWriter._();

  /// Best-effort: tags [path] with the given fields, returning true if it
  /// worked. Any failure (unsupported layout, corrupt input, I/O error)
  /// leaves the file exactly as it was and returns false — a track missing
  /// metadata is fine, a corrupted one is not.
  static Future<bool> tag(
    String path, {
    required String title,
    required String artist,
    String? comment,
    int? year,
    Uint8List? coverArtJpeg,
  }) async {
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final tagged = _tag(
        bytes,
        title: title,
        artist: artist,
        comment: comment,
        year: year,
        coverArtJpeg: coverArtJpeg,
      );
      if (tagged == null) return false;
      final tempFile = File('$path.tag.tmp');
      await tempFile.writeAsBytes(tagged, flush: true);
      if (!_looksStructurallyValid(await tempFile.readAsBytes())) {
        await tempFile.delete();
        return false;
      }
      await tempFile.rename(path);
      return true;
    } catch (_) {
      try {
        final tempFile = File('$path.tag.tmp');
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
      return false;
    }
  }

  static Uint8List? _tag(
    Uint8List bytes, {
    required String title,
    required String artist,
    String? comment,
    int? year,
    Uint8List? coverArtJpeg,
  }) {
    final top = _readBoxes(bytes, 0, bytes.length);
    final moov = _findBox(top, 'moov');
    final mdat = _findBox(top, 'mdat');
    if (moov == null || mdat == null) return null;
    // A fragmented file (moof) or a segment index (sidx) would need offset
    // patching this doesn't attempt — leave it alone rather than guess.
    if (_findBox(top, 'moof') != null || _findBox(top, 'sidx') != null) {
      return null;
    }
    if (top.where((b) => b.type == 'mdat').length > 1) return null;

    final children = _readBoxes(bytes, moov.payloadStart, moov.end);

    final ilst = _buildIlst(
      title: title,
      artist: artist,
      comment: comment,
      year: year,
      coverArtJpeg: coverArtJpeg,
    );
    final udta = _buildUdta(ilst);

    // Drop any pre-existing `udta` (this pipeline only ever tags a freshly
    // downloaded, untagged stream, so there is nothing worth preserving in
    // one) and append the freshly built one.
    final builder = BytesBuilder();
    for (final child in children) {
      if (child.type == 'udta') continue;
      builder.add(bytes.sublist(child.start, child.end));
    }
    builder.add(udta);
    final newMoovPayload = builder.toBytes();
    final newMoov = _box('moov', newMoovPayload);

    final delta = newMoov.length - (moov.end - moov.start);
    var patchedMoov = newMoov;
    if (delta != 0 && moov.start < mdat.start) {
      // Everything from the end of moov onward (including mdat) shifts by
      // `delta` bytes, so every absolute chunk offset stored inside moov
      // has to move with it.
      final patched = _shiftChunkOffsets(newMoov, delta);
      if (patched == null) return null; // couldn't verify every table
      patchedMoov = patched;
    }

    final result = BytesBuilder();
    result.add(bytes.sublist(0, moov.start));
    result.add(patchedMoov);
    result.add(bytes.sublist(moov.end, bytes.length));
    return result.toBytes();
  }

  /// Adds [delta] to every entry of every `stco`/`co64` box found anywhere
  /// inside [moovBytes] (a full `moov` box, header included). Returns null
  /// if a table looks inconsistent, since guessing wrong here would point
  /// the player at the wrong bytes for every chunk in the file.
  static Uint8List? _shiftChunkOffsets(Uint8List moovBytes, int delta) {
    final out = Uint8List.fromList(moovBytes);
    final ok = _walkContainers(out, 8, out.length, (box) {
      if (box.type == 'stco') {
        return _shiftOffsetTable(out, box, entryBytes: 4, delta: delta);
      }
      if (box.type == 'co64') {
        return _shiftOffsetTable(out, box, entryBytes: 8, delta: delta);
      }
      return true;
    });
    return ok ? out : null;
  }

  static bool _shiftOffsetTable(
    Uint8List data,
    _Box box, {
    required int entryBytes,
    required int delta,
  }) {
    final payloadStart = box.payloadStart;
    final payloadLen = box.end - payloadStart;
    if (payloadLen < 8) return false;
    final view = ByteData.sublistView(data);
    final entryCount = view.getUint32(payloadStart + 4);
    final expected = 8 + entryCount * entryBytes;
    if (expected != payloadLen) return false;
    for (var i = 0; i < entryCount; i++) {
      final offset = payloadStart + 8 + i * entryBytes;
      if (entryBytes == 4) {
        final value = view.getUint32(offset) + delta;
        if (value < 0 || value > 0xFFFFFFFF) return false;
        view.setUint32(offset, value);
      } else {
        final value = view.getUint64(offset) + delta;
        if (value < 0) return false;
        view.setUint64(offset, value);
      }
    }
    return true;
  }

  /// Recursively visits every box inside [start, end) that can plausibly
  /// contain nested boxes (the ones a real MP4's sample tables are nested
  /// under), calling [visit] on every box found. Stops and returns false
  /// the first time [visit] does.
  static const _containerTypes = {
    'moov',
    'trak',
    'mdia',
    'minf',
    'stbl',
    'udta',
    'edts',
  };

  static bool _walkContainers(
    Uint8List data,
    int start,
    int end,
    bool Function(_Box box) visit,
  ) {
    for (final box in _readBoxes(data, start, end)) {
      if (!visit(box)) return false;
      if (_containerTypes.contains(box.type)) {
        // `meta` is the odd one out: its payload starts with a 4-byte
        // version/flags field before the child boxes, but this app never
        // needs to walk into a pre-existing `meta` (it always rebuilds
        // `udta` from scratch), so it is deliberately not in the list.
        if (!_walkContainers(data, box.payloadStart, box.end, visit)) {
          return false;
        }
      }
    }
    return true;
  }

  static _Box? _findBox(List<_Box> boxes, String type) {
    for (final b in boxes) {
      if (b.type == type) return b;
    }
    return null;
  }

  /// Parses sibling box headers in `[start, end)`. Stops (without throwing)
  /// at the first box whose declared size doesn't fit, since that means
  /// this isn't a layout worth trusting further.
  static List<_Box> _readBoxes(Uint8List data, int start, int end) {
    final boxes = <_Box>[];
    final view = ByteData.sublistView(data);
    var offset = start;
    while (offset + 8 <= end) {
      final declaredSize = view.getUint32(offset);
      final type = ascii.decode(
        data.sublist(offset + 4, offset + 8),
        allowInvalid: true,
      );
      var headerLen = 8;
      int size;
      if (declaredSize == 1) {
        if (offset + 16 > end) break;
        size = view.getUint64(offset + 8);
        headerLen = 16;
      } else if (declaredSize == 0) {
        size = end - offset; // extends to the end of the parent
      } else {
        size = declaredSize;
      }
      if (size < headerLen || offset + size > end) break;
      boxes.add(_Box(
        type: type,
        start: offset,
        payloadStart: offset + headerLen,
        end: offset + size,
      ));
      offset += size;
    }
    return boxes;
  }

  /// A structural sanity check on a whole file's worth of bytes: the
  /// top-level boxes must account for every byte, `ftyp`/`moov`/`mdat` must
  /// still be there, and `moov` must still parse into at least one child —
  /// enough to catch an off-by-one in the splicing above without fully
  /// re-validating the sample tables.
  static bool _looksStructurallyValid(Uint8List bytes) {
    final top = _readBoxes(bytes, 0, bytes.length);
    if (top.isEmpty) return false;
    if (top.last.end != bytes.length) return false;
    final moov = _findBox(top, 'moov');
    if (moov == null || _findBox(top, 'mdat') == null) return false;
    return _readBoxes(bytes, moov.payloadStart, moov.end).isNotEmpty;
  }

  static Uint8List _box(String type, Uint8List payload) {
    final builder = BytesBuilder();
    builder.add(_u32(8 + payload.length));
    builder.add(ascii.encode(type));
    builder.add(payload);
    return builder.toBytes();
  }

  static Uint8List _u32(int value) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, value);

  static Uint8List _udtaMetaHdlr() {
    // The fixed boilerplate `hdlr` box every iTunes-style `meta` needs to
    // be recognised as metadata rather than ignored: version/flags(4) +
    // predefined(4) + handler_type('mdir') + reserved(12) + name(1, empty).
    final payload = BytesBuilder()
      ..add(_u32(0))
      ..add(_u32(0))
      ..add(ascii.encode('mdir'))
      ..add(Uint8List(12))
      ..addByte(0);
    return _box('hdlr', payload.toBytes());
  }

  static Uint8List _buildUdta(Uint8List ilst) {
    final metaPayload = BytesBuilder()
      ..add(_u32(0)) // meta's own version/flags
      ..add(_udtaMetaHdlr())
      ..add(ilst);
    return _box('udta', _box('meta', metaPayload.toBytes()));
  }

  static Uint8List _buildIlst({
    required String title,
    required String artist,
    String? comment,
    int? year,
    Uint8List? coverArtJpeg,
  }) {
    final builder = BytesBuilder();
    if (title.isNotEmpty) {
      builder.add(_textItem('©nam', title));
    }
    if (artist.isNotEmpty) {
      builder.add(_textItem('©ART', artist));
      builder.add(_textItem('aART', artist));
    }
    if (comment != null && comment.isNotEmpty) {
      builder.add(_textItem('©cmt', comment));
    }
    if (year != null) {
      builder.add(_textItem('©day', year.toString()));
    }
    if (coverArtJpeg != null && coverArtJpeg.isNotEmpty) {
      builder.add(_dataItem('covr', 13, coverArtJpeg)); // 13 = JPEG
    }
    return _box('ilst', builder.toBytes());
  }

  static Uint8List _textItem(String fourcc, String value) =>
      _dataItem(fourcc, 1, utf8.encode(value)); // 1 = UTF-8

  /// One `ilst` entry: `<fourcc> { data { version/flags(type) + locale(0) +
  /// payload } }` — the standard iTunes metadata atom shape.
  static Uint8List _dataItem(String fourcc, int wellKnownType, List<int> payload) {
    final dataPayload = BytesBuilder()
      ..add(_u32(wellKnownType))
      ..add(_u32(0))
      ..add(payload);
    final dataBox = _box('data', dataPayload.toBytes());
    final builder = BytesBuilder();
    builder.add(_u32(8 + dataBox.length));
    builder.add(_fourccBytes(fourcc));
    builder.add(dataBox);
    return builder.toBytes();
  }

  /// Encodes a box type that may start with the `©` iTunes marker
  /// (`U+00A9`, encoded as the single byte `0xA9` in these atoms, not
  /// UTF-8's two-byte form).
  static Uint8List _fourccBytes(String fourcc) {
    final out = Uint8List(4);
    for (var i = 0; i < 4; i++) {
      final code = fourcc.codeUnitAt(i);
      out[i] = code == 0x00a9 ? 0xa9 : code;
    }
    return out;
  }
}

class _Box {
  _Box({
    required this.type,
    required this.start,
    required this.payloadStart,
    required this.end,
  });

  final String type;
  final int start;
  final int payloadStart;
  final int end;
}
