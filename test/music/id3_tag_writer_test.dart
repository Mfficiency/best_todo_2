import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:besttodo/services/id3_tag_writer.dart';
import 'package:besttodo/services/music_metadata_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake "audio": recognizable bytes that must survive untouched.
final Uint8List _audio =
    Uint8List.fromList(List.generate(5000, (i) => (i * 7 + 3) & 0xff));

List<int> _synchsafe(int n) =>
    [(n >> 21) & 0x7f, (n >> 14) & 0x7f, (n >> 7) & 0x7f, n & 0x7f];

List<int> _frame(String id, String text, int major) {
  final data = [0x00, ...latin1.encode(text)];
  final n = data.length;
  final size = major == 4
      ? _synchsafe(n)
      : [(n >> 24) & 0xff, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff];
  return [...id.codeUnits, ...size, 0, 0, ...data];
}

/// An ID3v2.[major] tag holding [frames] plus [padding] zero bytes.
List<int> _tag(int major, List<List<int>> frames,
    {int padding = 0, int flags = 0}) {
  final body = [for (final f in frames) ...f, ...List.filled(padding, 0)];
  return [0x49, 0x44, 0x33, major, 0, flags, ..._synchsafe(body.length), ...body];
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('besttodo_id3_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<File> mp3(List<int> tag) async {
    final f = File('${dir.path}/song.mp3');
    await f.writeAsBytes([...tag, ..._audio]);
    return f;
  }

  Future<ExtractedTags> readTags(File f) async =>
      decodeMp3Tags(await f.readAsBytes());

  Future<Uint8List> audioOf(File f) async {
    final bytes = await f.readAsBytes();
    return Uint8List.sublistView(bytes, bytes.length - _audio.length);
  }

  test('adds missing frames into the padding, in place', () async {
    final f = await mp3(_tag(3, [_frame('TIT2', 'My Song', 3)], padding: 512));
    final lengthBefore = await f.length();
    final result = await Id3TagWriter.addMissing(
        f.path,
        const Id3Fields(
            title: 'Other title', artist: 'Band', genre: 'Rock', year: 1999,
            bpm: 128));
    expect(result, Id3WriteResult.written);
    expect(await f.length(), lengthBefore, reason: 'fit in the padding');
    final tags = await readTags(f);
    expect(tags.title, 'My Song', reason: 'an existing frame is kept');
    expect(tags.artist, 'Band');
    expect(tags.genre, 'Rock');
    expect(tags.year, 1999);
    expect(tags.bpm, 128);
    expect(await audioOf(f), _audio);
  });

  test('grows the tag (rewriting the file) when the padding is too small',
      () async {
    final f = await mp3(_tag(3, [_frame('TIT2', 'My Song', 3)]));
    final result = await Id3TagWriter.addMissing(
        f.path, const Id3Fields(album: 'Greatest Hits', bpm: 90));
    expect(result, Id3WriteResult.written);
    final tags = await readTags(f);
    expect(tags.title, 'My Song');
    expect(tags.album, 'Greatest Hits');
    expect(tags.bpm, 90);
    expect(await audioOf(f), _audio);
    expect(File('${f.path}.besttodo-tag.tmp').existsSync(), isFalse);
  });

  test('creates a tag on an mp3 that has none', () async {
    final f = await mp3([]);
    final result = await Id3TagWriter.addMissing(
        f.path, const Id3Fields(title: 'Café', artist: 'Ünïcode 日本'));
    expect(result, Id3WriteResult.written);
    final tags = await readTags(f);
    expect(tags.title, 'Café');
    expect(tags.artist, 'Ünïcode 日本');
    expect(await audioOf(f), _audio);
  });

  test('ID3v2.4 tags get TDRC and synchsafe frame sizes', () async {
    final f = await mp3(_tag(4, [_frame('TPE1', 'Band', 4)], padding: 256));
    final result = await Id3TagWriter.addMissing(
        f.path, const Id3Fields(artist: 'Ignored', year: 2005, bpm: 100));
    expect(result, Id3WriteResult.written);
    final bytes = await f.readAsBytes();
    expect(latin1.decode(bytes.sublist(0, 400), allowInvalid: true),
        contains('TDRC'));
    final tags = await readTags(f);
    expect(tags.artist, 'Band');
    expect(tags.year, 2005);
    expect(tags.bpm, 100);
  });

  test('a file that already has everything is left alone', () async {
    final tag = _tag(3, [
      _frame('TPE1', 'Band', 3),
      _frame('TBPM', '120', 3),
    ], padding: 64);
    final f = await mp3(tag);
    final before = await f.readAsBytes();
    expect(
        await Id3TagWriter.addMissing(
            f.path, const Id3Fields(artist: 'X', bpm: 99)),
        Id3WriteResult.nothingToAdd);
    expect(await f.readAsBytes(), before);
  });

  test('an empty frame counts as missing', () async {
    final f = await mp3(_tag(3, [_frame('TCON', '', 3)], padding: 128));
    expect(await Id3TagWriter.addMissing(f.path, const Id3Fields(genre: 'Jazz')),
        Id3WriteResult.written);
    expect((await readTags(f)).genre, 'Jazz');
  });

  test('unusual tags and non-mp3 files are never touched', () async {
    final f = await mp3(_tag(3, [_frame('TIT2', 'X', 3)], flags: 0x80));
    final before = await f.readAsBytes();
    expect(await Id3TagWriter.addMissing(f.path, const Id3Fields(bpm: 1)),
        Id3WriteResult.unsupported);
    expect(await f.readAsBytes(), before);

    final m4a = File('${dir.path}/song.m4a')..writeAsBytesSync(_audio);
    expect(await Id3TagWriter.addMissing(m4a.path, const Id3Fields(bpm: 1)),
        Id3WriteResult.unsupported);
  });

  test('a missing file fails', () async {
    expect(
        await Id3TagWriter.addMissing(
            '${dir.path}/gone.mp3', const Id3Fields(bpm: 1)),
        Id3WriteResult.failed);
  });

  test('keeps the modified time', () async {
    final f = await mp3(_tag(3, [], padding: 0));
    final old = DateTime(2020, 1, 2, 3, 4, 5);
    await f.setLastModified(old);
    await Id3TagWriter.addMissing(f.path, const Id3Fields(bpm: 77));
    expect(await f.lastModified(), old);
  });
}
