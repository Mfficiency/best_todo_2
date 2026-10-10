import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/gcal_event.dart';

/// Imports events from a public .ics feed (a Google Calendar "Secret address
/// in iCal format" URL, or any other RFC 5545 feed), keeps a disk cache of
/// the parsed-but-unexpanded events so the app has something to show
/// offline, and expands recurring events (RRULE) on demand for whatever
/// date range is being viewed.
class GoogleCalendarService {
  GoogleCalendarService._();

  static const _cacheFileName = 'google_calendar_cache.json';

  /// Test hook: overrides the network fetch so tests never hit the network.
  static Future<String> Function(Uri url)? fetchOverride;

  static Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_cacheFileName');
  }

  /// Downloads and parses the feed at [url], caches the raw events to disk
  /// and returns them. Throws on a network or parse failure — callers show
  /// the error and keep whatever was cached from a previous import.
  static Future<List<GCalRawEvent>> refresh(String url) async {
    final text = await _fetch(Uri.parse(url));
    final events = parseIcs(text);
    await _saveCache(url, events);
    return events;
  }

  /// The events from the last successful import, or an empty list if nothing
  /// has been imported yet (or the cache is unreadable).
  static Future<List<GCalRawEvent>> loadCached() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return const [];
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final list = data['events'] as List? ?? const [];
      return [
        for (final e in list)
          GCalRawEvent.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// When the cache was last refreshed, or null if never.
  static Future<DateTime?> lastRefreshed() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return null;
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final raw = data['fetchedAt'] as String?;
      return raw == null ? null : DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearCache() async {
    try {
      final file = await _cacheFile();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<void> _saveCache(String url, List<GCalRawEvent> events) async {
    try {
      final file = await _cacheFile();
      final data = {
        'sourceUrl': url,
        'fetchedAt': DateTime.now().toIso8601String(),
        'events': [for (final e in events) e.toJson()],
      };
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {}
  }

  static Future<String> _fetch(Uri url) async {
    final override = fetchOverride;
    if (override != null) return override(url);
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.acceptHeader, 'text/calendar');
      request.headers
          .set(HttpHeaders.userAgentHeader, 'BestToDo-calendar-import');
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw HttpException(
            'Calendar server replied ${response.statusCode}', uri: url);
      }
      return text;
    } finally {
      client.close();
    }
  }

  // ---- ICS parsing ----

  /// Parses raw .ics text into its VEVENT blocks. Public (and side-effect
  /// free) so it can be unit tested without any network or disk access.
  static List<GCalRawEvent> parseIcs(String icsText) {
    final lines = _unfold(icsText);
    final events = <GCalRawEvent>[];

    Map<String, String>? props;
    List<String>? exdateLines;
    for (final line in lines) {
      if (line == 'BEGIN:VEVENT') {
        props = {};
        exdateLines = [];
        continue;
      }
      if (line == 'END:VEVENT') {
        if (props != null) {
          final event = _eventFromProps(props, exdateLines ?? const []);
          if (event != null) events.add(event);
        }
        props = null;
        exdateLines = null;
        continue;
      }
      if (props == null) continue; // outside a VEVENT block

      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final rawName = line.substring(0, colon).toUpperCase();
      final value = line.substring(colon + 1);
      final name = rawName.split(';').first;

      if (name == 'EXDATE') {
        exdateLines?.add(value);
        continue;
      }
      // Keyed by the full "NAME;PARAMS" string so VALUE=DATE can be
      // recovered later; a repeated property (e.g. multiple DESCRIPTION
      // lines) just keeps the last one, which is fine for the fields this
      // parser reads.
      props[rawName] = value;
    }
    return events;
  }

  static GCalRawEvent? _eventFromProps(
    Map<String, String> props,
    List<String> exdateLines,
  ) {
    String? valueFor(String name) {
      for (final key in props.keys) {
        if (key.split(';').first == name) return props[key];
      }
      return null;
    }

    bool isDateOnlyParam(String name) {
      for (final key in props.keys) {
        if (key.split(';').first == name) return key.contains('VALUE=DATE');
      }
      return false;
    }

    final dtStartRaw = valueFor('DTSTART');
    if (dtStartRaw == null) return null;
    final startAllDay = isDateOnlyParam('DTSTART') || _isDateOnly(dtStartRaw);
    final start = _parseIcsDateTime(dtStartRaw);
    if (start == null) return null;

    final dtEndRaw = valueFor('DTEND');
    DateTime end;
    if (dtEndRaw != null) {
      end = _parseIcsDateTime(dtEndRaw) ?? start;
    } else {
      final durationRaw = valueFor('DURATION');
      final parsedDuration =
          durationRaw != null ? _parseIcsDuration(durationRaw) : null;
      end = parsedDuration != null
          ? start.add(parsedDuration)
          : (startAllDay ? start.add(const Duration(days: 1)) : start);
    }

    final title = _unescapeText(valueFor('SUMMARY') ?? '(untitled)');
    final uid = valueFor('UID') ?? '${start.millisecondsSinceEpoch}-$title';
    final rrule = valueFor('RRULE');
    final exdates = <DateTime>[
      for (final raw in exdateLines)
        for (final part in raw.split(','))
          if (_parseIcsDateTime(part) != null) _parseIcsDateTime(part)!,
    ];

    return GCalRawEvent(
      uid: uid,
      title: title,
      start: start,
      end: end,
      allDay: startAllDay,
      rrule: rrule,
      exdates: exdates,
    );
  }

  /// Joins RFC 5545 folded lines (a continuation starts with a space or tab)
  /// back into one logical line per property, and drops blank lines.
  static List<String> _unfold(String icsText) {
    final rawLines = icsText.split(RegExp(r'\r\n|\n|\r'));
    final result = <String>[];
    for (final line in rawLines) {
      if (line.isEmpty) continue;
      if ((line.startsWith(' ') || line.startsWith('\t')) &&
          result.isNotEmpty) {
        result[result.length - 1] += line.substring(1);
      } else {
        result.add(line);
      }
    }
    return result;
  }

  static bool _isDateOnly(String value) => RegExp(r'^\d{8}$').hasMatch(value);

  static DateTime? _parseIcsDateTime(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (RegExp(r'^\d{8}$').hasMatch(value)) {
      final y = int.parse(value.substring(0, 4));
      final m = int.parse(value.substring(4, 6));
      final d = int.parse(value.substring(6, 8));
      return DateTime(y, m, d);
    }
    final match = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z)?$')
        .firstMatch(value);
    if (match == null) return null;
    final y = int.parse(match.group(1)!);
    final mo = int.parse(match.group(2)!);
    final d = int.parse(match.group(3)!);
    final h = int.parse(match.group(4)!);
    final mi = int.parse(match.group(5)!);
    final s = int.parse(match.group(6)!);
    final isUtc = match.group(7) != null;
    return isUtc
        ? DateTime.utc(y, mo, d, h, mi, s).toLocal()
        : DateTime(y, mo, d, h, mi, s);
  }

  /// Minimal ISO-8601 duration support (PnDTnHnMnS) — enough for the
  /// DURATION values calendar exports actually use.
  static Duration? _parseIcsDuration(String raw) {
    final match = RegExp(
      r'^([+-]?)P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
    ).firstMatch(raw.trim());
    if (match == null) return null;
    final sign = match.group(1) == '-' ? -1 : 1;
    final days = int.tryParse(match.group(2) ?? '0') ?? 0;
    final hours = int.tryParse(match.group(3) ?? '0') ?? 0;
    final minutes = int.tryParse(match.group(4) ?? '0') ?? 0;
    final seconds = int.tryParse(match.group(5) ?? '0') ?? 0;
    return Duration(
      days: sign * days,
      hours: sign * hours,
      minutes: sign * minutes,
      seconds: sign * seconds,
    );
  }

  static String _unescapeText(String value) => value
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\N', '\n')
      .replaceAll(r'\,', ',')
      .replaceAll(r'\;', ';')
      .replaceAll(r'\\', r'\');

  // ---- Recurrence expansion ----

  /// Expands [raw] events into concrete occurrences overlapping
  /// `[rangeStart, rangeEnd)` — the window being shown.
  /// Non-recurring events are just filtered by overlap.
  static List<GCalEvent> eventsInRange(
    List<GCalRawEvent> raw,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final result = <GCalEvent>[];
    for (final event in raw) {
      final duration = event.end.difference(event.start);
      if (event.rrule == null) {
        if (event.end.isAfter(rangeStart) && event.start.isBefore(rangeEnd)) {
          result.add(GCalEvent(
            uid: event.uid,
            title: event.title,
            start: event.start,
            end: event.end,
            allDay: event.allDay,
          ));
        }
        continue;
      }
      final rule = _RRule.parse(event.rrule!);
      if (rule == null) continue;
      var count = 0;
      for (final occStart in _occurrenceStarts(event.start, rule, rangeEnd)) {
        if (rule.until != null && occStart.isAfter(rule.until!)) break;
        if (rule.count != null && count >= rule.count!) break;
        count++;
        if (event.exdates.any((ex) => _isSameInstant(ex, occStart))) continue;
        final occEnd = occStart.add(duration);
        if (occEnd.isAfter(rangeStart) && occStart.isBefore(rangeEnd)) {
          result.add(GCalEvent(
            uid: '${event.uid}#${occStart.toIso8601String()}',
            title: event.title,
            start: occStart,
            end: occEnd,
            allDay: event.allDay,
          ));
        }
      }
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  /// True when [a] (an EXDATE) refers to the same occurrence as [b]. An
  /// EXDATE given as a bare date (parsed at midnight) excludes that whole
  /// day's occurrence regardless of its time of day.
  static bool _isSameInstant(DateTime a, DateTime b) {
    if (a.year != b.year || a.month != b.month || a.day != b.day) {
      return false;
    }
    if (a.hour == 0 && a.minute == 0 && a.second == 0) return true;
    return a.hour == b.hour && a.minute == b.minute;
  }

  /// Candidate occurrence start times for [rule], from [seed] up to (but not
  /// including) [rangeEnd]. Bounded by construction: every branch only steps
  /// forward and stops once it reaches rangeEnd (with a small extra guard for
  /// monthly/yearly, whose step size can undershoot near month-end clamps),
  /// so this always terminates.
  static Iterable<DateTime> _occurrenceStarts(
    DateTime seed,
    _RRule rule,
    DateTime rangeEnd,
  ) sync* {
    switch (rule.freq) {
      case 'DAILY':
        var d = seed;
        while (d.isBefore(rangeEnd)) {
          yield d;
          d = d.add(Duration(days: rule.interval));
        }
        break;
      case 'WEEKLY':
        if (rule.byDay.isEmpty) {
          var d = seed;
          while (d.isBefore(rangeEnd)) {
            yield d;
            d = d.add(Duration(days: 7 * rule.interval));
          }
        } else {
          final seedWeekStart =
              seed.subtract(Duration(days: seed.weekday - 1));
          var weekStart = DateTime(
              seedWeekStart.year, seedWeekStart.month, seedWeekStart.day);
          final sortedDays = rule.byDay.toList()..sort();
          while (weekStart.isBefore(rangeEnd)) {
            for (final wd in sortedDays) {
              final occDate = weekStart.add(Duration(days: wd - 1));
              final occ = DateTime(occDate.year, occDate.month, occDate.day,
                  seed.hour, seed.minute, seed.second);
              if (!occ.isBefore(seed) && occ.isBefore(rangeEnd)) yield occ;
            }
            weekStart = weekStart.add(Duration(days: 7 * rule.interval));
          }
        }
        break;
      case 'MONTHLY':
        var d = seed;
        var guard = 0;
        while (d.isBefore(rangeEnd) && guard < 600) {
          yield d;
          guard++;
          final total = d.month - 1 + rule.interval;
          final year = d.year + total ~/ 12;
          final month = total % 12 + 1;
          final lastDay = DateTime(year, month + 1, 0).day;
          final day = d.day > lastDay ? lastDay : d.day;
          d = DateTime(year, month, day, d.hour, d.minute, d.second);
        }
        break;
      case 'YEARLY':
        var d = seed;
        var guard = 0;
        while (d.isBefore(rangeEnd) && guard < 200) {
          yield d;
          guard++;
          d = DateTime(
              d.year + rule.interval, d.month, d.day, d.hour, d.minute, d.second);
        }
        break;
    }
  }
}

/// A minimally-parsed RRULE: enough to expand DAILY/WEEKLY/MONTHLY/YEARLY
/// recurrences with INTERVAL, COUNT, UNTIL and (for WEEKLY) BYDAY.
class _RRule {
  final String freq;
  final int interval;
  final int? count;
  final DateTime? until;
  final Set<int> byDay; // DateTime.weekday convention: Mon=1..Sun=7

  const _RRule({
    required this.freq,
    this.interval = 1,
    this.count,
    this.until,
    this.byDay = const {},
  });

  static const _dayCodes = {
    'MO': 1,
    'TU': 2,
    'WE': 3,
    'TH': 4,
    'FR': 5,
    'SA': 6,
    'SU': 7,
  };

  static const _supportedFreqs = {'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'};

  static _RRule? parse(String rule) {
    String? freq;
    var interval = 1;
    int? count;
    DateTime? until;
    final byDay = <int>{};
    for (final part in rule.split(';')) {
      final kv = part.split('=');
      if (kv.length != 2) continue;
      final key = kv[0].toUpperCase();
      final value = kv[1];
      switch (key) {
        case 'FREQ':
          freq = value.toUpperCase();
          break;
        case 'INTERVAL':
          interval = int.tryParse(value) ?? 1;
          break;
        case 'COUNT':
          count = int.tryParse(value);
          break;
        case 'UNTIL':
          until = GoogleCalendarService._parseIcsDateTime(value);
          break;
        case 'BYDAY':
          for (final code in value.split(',')) {
            // Strip a leading ordinal (e.g. "2MO") — not supported, treated
            // as a plain weekday match.
            final letters = code.replaceAll(RegExp(r'^[-+]?\d*'), '');
            final wd = _dayCodes[letters.toUpperCase()];
            if (wd != null) byDay.add(wd);
          }
          break;
      }
    }
    if (freq == null || !_supportedFreqs.contains(freq)) return null;
    return _RRule(
      freq: freq,
      interval: interval < 1 ? 1 : interval,
      count: count,
      until: until,
      byDay: byDay,
    );
  }
}
