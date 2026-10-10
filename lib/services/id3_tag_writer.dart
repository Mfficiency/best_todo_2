import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'music_metadata_extractor.dart';

/// What [Id3TagWriter.addMissing] did to a file.
enum Id3WriteResult {
  /// New frames were written.
  written,

  /// The file already had every given field — untouched.
  nothingToAdd,

  /// Not an mp3, or a tag layout this writer deliberately doesn't touch
  /// (ID3v2.2, unsynchronisation, extended header, footer) — untouched.
  unsupported,

  /// I/O error (no permission, file gone) — untouched; worth retrying.
  failed,
}

/// Fields to add to an mp3's ID3v2 tag. Null/blank = leave alone.
class Id3Fields {
  const Id3Fields(
      {this.title, this.artist, this.album, this.genre, this.year, this.bpm});

  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final int? year;
  final int? bpm;
}

/// Writes the metadata Best Music found online/on device back into the
/// mp3 itself, so other players and a fresh install see it too
/// (`MusicMetadataEnricher`). Fill-only, like the rest of that feature: a
/// frame the file already has with any text in it is never changed — only
/// absent (or empty) TIT2/TPE1/TALB/TCON/TYER(v2.3)·TDRC(v2.4)/TBPM frames
/// are added. Every other frame (cover art, lyrics, comments, ...) is
/// copied through byte for byte.
///
/// Conservative by design — a track missing a tag is fine, a corrupted one
/// is not: anything unusual bails out with [Id3WriteResult.unsupported],
/// the new tag is decoded again before anything touches the disk, and the
/// audio is never rewritten in place. When the new tag fits in the old
/// one's padding only the tag bytes at the start are overwritten;
/// otherwise a tagged copy is written next to the file, its length
/// checked, and renamed over the original. The file's modified time is
/// restored afterwards.
class Id3TagWriter {
  const Id3TagWriter._();

  static const int _newPadding = 2048;

  static Future<Id3WriteResult> addMissing(String path, Id3Fields fields) async {
    if (!path.toLowerCase().endsWith('.mp3')) return Id3WriteResult.unsupported;
    final file = File(path);
    RandomAccessFile? raf;
    try {
      final modified = await file.lastModified();
      raf = await file.open();
      final fileLength = await raf.length();
      final header = await raf.read(10);
      var major = 3;
      var oldTotal = 0; // header + body of the existing tag, 0 if none
      final frames = <_Frame>[];
      if (header.length == 10 &&
          header[0] == 0x49 && // I
          header[1] == 0x44 && // D
          header[2] == 0x33) {
        // 3
        major = header[3];
        final flags = header[5];
        if (major != 3 && major != 4) return Id3WriteResult.unsupported;
        if (flags & 0xF0 != 0) return Id3WriteResult.unsupported;
        final bodySize = _synchsafe(header, 6);
        oldTotal = 10 + bodySize;
        if (oldTotal > fileLength) return Id3WriteResult.unsupported;
        final body = await raf.read(bodySize);
        if (body.length != bodySize) return Id3WriteResult.unsupported;
        if (!_parseFrames(body, major, frames)) {
          return Id3WriteResult.unsupported;
        }
      }
      await raf.close();
      raf = null;

      final yearId = major == 4 ? 'TDRC' : 'TYER';
      final additions = <String, String>{
        if (_blank(fields.title) == false) 'TIT2': fields.title!.trim(),
        if (_blank(fields.artist) == false) 'TPE1': fields.artist!.trim(),
        if (_blank(fields.album) == false) 'TALB': fields.album!.trim(),
        if (_blank(fields.genre) == false) 'TCON': fields.genre!.trim(),
        if (fields.year != null) yearId: '${fields.year}',
        if (fields.bpm != null) 'TBPM': '${fields.bpm}',
      };
      bool hasText(String id) => frames.any((f) => f.id == id && f.hasText);
      additions.removeWhere((id, _) =>
          hasText(id) ||
          ((id == 'TYER' || id == 'TDRC') &&
              (hasText('TYER') || hasText('TDRC'))));
      if (additions.isEmpty) return Id3WriteResult.nothingToAdd;

      // Drop the empty placeholders being replaced; keep everything else.
      frames.removeWhere((f) => additions.containsKey(f.id));
      final framesBytes = BytesBuilder(copy: false);
      for (final f in frames) {
        framesBytes.add(f.raw);
      }
      additions.forEach((id, text) {
        framesBytes.add(_textFrame(id, text, major));
      });
      final framesLength = framesBytes.length;
      final inPlace = oldTotal > 0 && 10 + framesLength <= oldTotal;
      final total = inPlace ? oldTotal : 10 + framesLength + _newPadding;
      final tag = Uint8List(total);
      tag.setRange(0, 10, [
        0x49, 0x44, 0x33, major, 0, 0, //
        ..._toSynchsafe(total - 10),
      ]);
      tag.setRange(10, 10 + framesLength, framesBytes.takeBytes());

      // Read it back before touching the file.
      final check = decodeMp3Tags(tag);
      if (additions.containsKey('TBPM') && check.bpm != fields.bpm) {
        return Id3WriteResult.unsupported;
      }
      if (additions.containsKey('TPE1') &&
          check.artist?.trim() != fields.artist?.trim()) {
        return Id3WriteResult.unsupported;
      }

      if (inPlace) {
        raf = await file.open(mode: FileMode.append);
        await raf.setPosition(0);
        await raf.writeFrom(tag);
        await raf.flush();
        await raf.close();
        raf = null;
      } else {
        final tmp = File('$path.besttodo-tag.tmp');
        final sink = tmp.openWrite();
        sink.add(tag);
        await sink.addStream(file.openRead(oldTotal));
        await sink.flush();
        await sink.close();
        final expected = tag.length + (fileLength - oldTotal);
        if (await tmp.length() != expected) {
          await tmp.delete();
          return Id3WriteResult.failed;
        }
        await tmp.rename(path);
      }
      try {
        await file.setLastModified(modified);
      } catch (_) {}
      return Id3WriteResult.written;
    } catch (_) {
      return Id3WriteResult.failed;
    } finally {
      await raf?.close();
    }
  }

  static bool? _blank(String? s) => s == null ? null : s.trim().isEmpty;

  static int _synchsafe(List<int> b, int o) =>
      (b[o] & 0x7f) << 21 |
      (b[o + 1] & 0x7f) << 14 |
      (b[o + 2] & 0x7f) << 7 |
      (b[o + 3] & 0x7f);

  static List<int> _toSynchsafe(int n) =>
      [(n >> 21) & 0x7f, (n >> 14) & 0x7f, (n >> 7) & 0x7f, n & 0x7f];

  static List<int> _bigEndian(int n) =>
      [(n >> 24) & 0xff, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff];

  /// Splits a tag body into frames; false on anything malformed.
  static bool _parseFrames(Uint8List body, int major, List<_Frame> out) {
    var pos = 0;
    while (pos + 10 <= body.length) {
      if (body[pos] == 0) break; // padding
      final id = String.fromCharCodes(body.sublist(pos, pos + 4));
      if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(id)) return false;
      final size = major == 4
          ? _synchsafe(body, pos + 4)
          : (body[pos + 4] << 24 |
              body[pos + 5] << 16 |
              body[pos + 6] << 8 |
              body[pos + 7]);
      final end = pos + 10 + size;
      if (size < 0 || end > body.length) return false;
      out.add(_Frame(id, Uint8List.sublistView(body, pos, end),
          Uint8List.sublistView(body, pos + 10, end)));
      pos = end;
    }
    return true;
  }

  static Uint8List _textFrame(String id, String text, int major) {
    final List<int> data;
    if (major == 4) {
      data = [0x03, ...utf8.encode(text)];
    } else if (text.codeUnits.every((c) => c <= 0xff)) {
      data = [0x00, ...latin1.encode(text)];
    } else {
      data = [0x01, 0xff, 0xfe];
      for (final unit in text.codeUnits) {
        data
          ..add(unit & 0xff)
          ..add(unit >> 8);
      }
    }
    final size = major == 4 ? _toSynchsafe(data.length) : _bigEndian(data.length);
    return Uint8List.fromList([...id.codeUnits, ...size, 0, 0, ...data]);
  }
}

class _Frame {
  _Frame(this.id, this.raw, this.data);

  final String id;
  final Uint8List raw;
  final Uint8List data;

  /// A text frame with something in it besides the encoding byte, BOMs and
  /// terminators.
  bool get hasText =>
      data.length > 1 &&
      data.skip(1).any((b) => b != 0 && b != 0xff && b != 0xfe);
}
