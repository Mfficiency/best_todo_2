import 'package:besttodo/models/playlist_rule.dart';
import 'package:besttodo/models/track.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Track track({
    String artist = '',
    String genre = '',
    int? year,
    String title = '',
    String album = '',
  }) =>
      Track.local(
        filePath: '/x.mp3',
        title: title,
        artist: artist,
        album: album,
        genre: genre,
        year: year,
      );

  group('RuleCondition', () {
    test('equals/notEquals are case-insensitive exact matches', () {
      final t = track(genre: 'Rock');
      const eq = RuleCondition(
          field: RuleField.genre, operator: RuleOperator.equals, values: ['rock']);
      const notEq = RuleCondition(
          field: RuleField.genre, operator: RuleOperator.notEquals, values: ['rock']);
      const eqOther = RuleCondition(
          field: RuleField.genre, operator: RuleOperator.equals, values: ['Pop']);

      expect(eq.matches(t), isTrue);
      expect(notEq.matches(t), isFalse);
      expect(eqOther.matches(t), isFalse);
    });

    test('contains/notContains do substring matching', () {
      final t = track(title: 'Bohemian Rhapsody');
      const has = RuleCondition(
          field: RuleField.title, operator: RuleOperator.contains, values: ['rhapsody']);
      const hasNot = RuleCondition(
          field: RuleField.title, operator: RuleOperator.notContains, values: ['queen']);

      expect(has.matches(t), isTrue);
      expect(hasNot.matches(t), isTrue);
    });

    test('inList matches "including multiple artists" (an OR within one condition)', () {
      final queen = track(artist: 'Queen');
      final abba = track(artist: 'ABBA');
      final other = track(artist: 'Someone Else');
      const condition = RuleCondition(
        field: RuleField.artist,
        operator: RuleOperator.inList,
        values: ['Queen', 'ABBA'],
      );

      expect(condition.matches(queen), isTrue);
      expect(condition.matches(abba), isTrue);
      expect(condition.matches(other), isFalse);
    });

    test('notInList excludes specific artists without affecting others', () {
      final excluded = track(artist: 'Artist C');
      final kept = track(artist: 'Artist A');
      const condition = RuleCondition(
        field: RuleField.artist,
        operator: RuleOperator.notInList,
        values: ['Artist C'],
      );

      expect(condition.matches(excluded), isFalse);
      expect(condition.matches(kept), isTrue);
    });

    test('an empty positive condition matches nothing; an empty negative one excludes nothing', () {
      final t = track(artist: 'Anyone');
      const emptyEquals =
          RuleCondition(field: RuleField.artist, operator: RuleOperator.equals);
      const emptyNotInList =
          RuleCondition(field: RuleField.artist, operator: RuleOperator.notInList);

      expect(emptyEquals.matches(t), isFalse);
      expect(emptyNotInList.matches(t), isTrue);
    });

    group('year (numeric field)', () {
      test('equals/greaterOrEqual/lessOrEqual compare as numbers', () {
        final t = track(year: 2020);
        const eq = RuleCondition(
            field: RuleField.year, operator: RuleOperator.equals, values: ['2020']);
        const ge = RuleCondition(
            field: RuleField.year, operator: RuleOperator.greaterOrEqual, values: ['2019']);
        const le = RuleCondition(
            field: RuleField.year, operator: RuleOperator.lessOrEqual, values: ['2019']);

        expect(eq.matches(t), isTrue);
        expect(ge.matches(t), isTrue);
        expect(le.matches(t), isFalse);
      });

      test('a track with no known year never matches a positive year condition', () {
        final t = track();
        const eq = RuleCondition(
            field: RuleField.year, operator: RuleOperator.equals, values: ['2020']);

        expect(eq.matches(t), isFalse);
      });

      test('contains/notContains are not meaningful for year and never match', () {
        final t = track(year: 2020);
        const condition = RuleCondition(
            field: RuleField.year, operator: RuleOperator.contains, values: ['2020']);

        expect(condition.matches(t), isFalse);
      });
    });

    test('toJson/fromJson round-trips', () {
      const condition = RuleCondition(
        field: RuleField.genre,
        operator: RuleOperator.inList,
        values: ['Rock', 'Pop'],
      );

      final restored = RuleCondition.fromJson(condition.toJson());

      expect(restored.field, RuleField.genre);
      expect(restored.operator, RuleOperator.inList);
      expect(restored.values, ['Rock', 'Pop']);
    });
  });

  group('PlaylistRuleSet', () {
    test('RuleCombinator.all requires every condition to match (AND)', () {
      final matchesBoth = track(genre: 'Rock', year: 2025);
      final matchesOne = track(genre: 'Rock', year: 2020);
      const ruleSet = PlaylistRuleSet(
        combinator: RuleCombinator.all,
        conditions: [
          RuleCondition(field: RuleField.genre, operator: RuleOperator.equals, values: ['Rock']),
          RuleCondition(field: RuleField.year, operator: RuleOperator.equals, values: ['2025']),
        ],
      );

      expect(ruleSet.matches(matchesBoth), isTrue);
      expect(ruleSet.matches(matchesOne), isFalse);
    });

    test('RuleCombinator.any requires just one condition to match (OR)', () {
      final matchesGenre = track(genre: 'Rock', year: 1999);
      final matchesNeither = track(genre: 'Jazz', year: 1999);
      const ruleSet = PlaylistRuleSet(
        combinator: RuleCombinator.any,
        conditions: [
          RuleCondition(field: RuleField.genre, operator: RuleOperator.equals, values: ['Rock']),
          RuleCondition(field: RuleField.year, operator: RuleOperator.equals, values: ['2025']),
        ],
      );

      expect(ruleSet.matches(matchesGenre), isTrue);
      expect(ruleSet.matches(matchesNeither), isFalse);
    });

    test('a rule set with no conditions matches nothing', () {
      expect(const PlaylistRuleSet().matches(track()), isFalse);
    });

    test('combines an inclusion OR with an exclusion NOT under one AND', () {
      // "Songs by Artist A or Artist B, excluding Artist C" from genre Rock.
      final artistA = track(artist: 'Artist A', genre: 'Rock');
      final artistC = track(artist: 'Artist C', genre: 'Rock');
      final otherGenre = track(artist: 'Artist A', genre: 'Jazz');
      const ruleSet = PlaylistRuleSet(
        combinator: RuleCombinator.all,
        conditions: [
          RuleCondition(field: RuleField.genre, operator: RuleOperator.equals, values: ['Rock']),
          RuleCondition(
              field: RuleField.artist,
              operator: RuleOperator.inList,
              values: ['Artist A', 'Artist B']),
          RuleCondition(
              field: RuleField.artist,
              operator: RuleOperator.notInList,
              values: ['Artist C']),
        ],
      );

      expect(ruleSet.matches(artistA), isTrue);
      expect(ruleSet.matches(artistC), isFalse);
      expect(ruleSet.matches(otherGenre), isFalse);
    });

    test('toJson/fromJson round-trips', () {
      const ruleSet = PlaylistRuleSet(
        combinator: RuleCombinator.any,
        conditions: [
          RuleCondition(field: RuleField.genre, operator: RuleOperator.equals, values: ['Rock']),
        ],
      );

      final restored = PlaylistRuleSet.fromJson(ruleSet.toJson());

      expect(restored.combinator, RuleCombinator.any);
      expect(restored.conditions, hasLength(1));
    });

    test('fromJson tolerates missing/malformed keys', () {
      final restored = PlaylistRuleSet.fromJson(const {});
      expect(restored.combinator, RuleCombinator.all);
      expect(restored.conditions, isEmpty);
    });
  });
}
