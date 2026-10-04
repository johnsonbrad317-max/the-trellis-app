import 'dart:io';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/rule_item.dart';
import 'package:trellis/models/rule_of_life_baseline.dart';
import 'package:trellis/models/watched_runner.dart';
import 'package:trellis/theme/app_colors.dart';
import 'package:trellis/theme/app_theme.dart';

/// Guards for defects found in the 1.0 pre-release audit, so they can't return.
void main() {
  _modelTests();
  _phase5Tests();

  group('starter baselines', () {
    test('every weekly rhythm has at least one day (the database rejects one without)', () {
      // rule_items has a constraint that a weekly rhythm must have days
      // (migration 013). "The Essential" is inserted for every new Runner at
      // sign-up, so one weekly item without days would fail account creation.
      for (final baseline in ruleOfLifeBaselines) {
        for (final item in baseline.items) {
          if (item.frequency == RuleFrequency.weekly) {
            expect(
              item.weeklyDays,
              isNotEmpty,
              reason: '"${item.title}" in "${baseline.name}" is weekly but has no days',
            );
          }
          expect(
            item.weeklyDays.every((d) => d >= DateTime.monday && d <= DateTime.sunday),
            isTrue,
            reason: '"${item.title}" has a weekday outside 1..7',
          );
        }
      }
    });

    test('the sign-up baseline exists and is not empty', () {
      expect(ruleOfLifeBaselines, isNotEmpty);
      expect(ruleOfLifeBaselines.first.items, isNotEmpty);
    });
  });

  group('WatchedRunner', () {
    test('a lock-removal request is off unless the server says otherwise', () {
      final runner = WatchedRunner(
        id: 'r',
        name: 'Ruth Example',
        ruleItems: const [],
        sharedPrayerRequests: const [],
        pendingMeetings: const [],
        confirmedMeetings: const [],
        witnessPrayers: const [],
        referenceDate: DateTime(2026, 10, 3),
      );
      expect(runner.lockRemovalRequested, isFalse);
    });
  });

  group('release hygiene (source scan)', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('there is something to scan', () => expect(dartFiles, isNotEmpty));

    test('no raw print() calls — diagnostics go through debugPrint, silenced in release', () {
      final offenders = <String>[];
      final printCall = RegExp(r'(^|[^\w.])print\(');
      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (printCall.hasMatch(line)) offenders.add('${file.path}:${i + 1}');
        }
      }
      expect(offenders, isEmpty);
    });

    test('no membership bypass or debug-only UI ships in the app', () {
      final offenders = <String>[];
      for (final file in dartFiles) {
        final source = file.readAsStringSync();
        if (source.contains('Dev Bypass') || source.contains('kDebugMode')) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('no stock Material icons — every glyph is hand-drawn', () {
      final offenders = <String>[];
      final iconUse = RegExp(r'\bIcons\.[a-z_]+');
      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (iconUse.hasMatch(line)) offenders.add('${file.path}:${i + 1}');
        }
      }
      expect(offenders, isEmpty);
    });
  });
}

// ---------------------------------------------------------------------------
// Model behaviour fixed in the audit
// ---------------------------------------------------------------------------
void _modelTests() {
  group('RuleItem.checkInPrompt', () {
    RuleItem item(String title) =>
        RuleItem(id: 'x', category: RuleCategory.abidingPrayer, title: title);

    test('reads as a sentence whether the title was typed or picked from a preset', () {
      expect(item('pray for 15 minutes').checkInPrompt, 'Did you pray for 15 minutes?');
      expect(
        item('Read Scripture for 15 Minutes').checkInPrompt,
        'Did you read Scripture for 15 Minutes?',
      );
    });

    test('leaves an acronym alone and survives very short titles', () {
      expect(item('AA meeting').checkInPrompt, 'Did you AA meeting?');
      expect(item('X').checkInPrompt, 'Did you X?');
      expect(item('').checkInPrompt, 'Did you ?');
    });
  });
}

// ---------------------------------------------------------------------------
// Phase 5: bundled type, one parchment, no placeholder controls
// ---------------------------------------------------------------------------
void _phase5Tests() {
  group('typeface', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    test('every EB Garamond file named in pubspec.yaml exists on disk', () {
      final assets = RegExp(r'asset:\s*(assets/fonts/\S+\.ttf)')
          .allMatches(pubspec)
          .map((m) => m.group(1)!)
          .toList();
      expect(assets, hasLength(10), reason: 'five weights, upright and italic');
      for (final asset in assets) {
        final file = File(asset);
        expect(file.existsSync(), isTrue, reason: '$asset is listed but missing');
        expect(file.lengthSync(), greaterThan(100000), reason: '$asset looks truncated');
      }
      expect(File('assets/fonts/OFL.txt').existsSync(), isTrue, reason: 'licence must ship');
    });

    test('the theme uses the bundled family and nothing is fetched at runtime', () {
      expect(pubspec.contains('family: ${AppTheme.fontFamily}'), isTrue);
      expect(pubspec.contains('google_fonts'), isFalse);
      final theme = AppTheme.light;
      expect(theme.textTheme.bodyMedium?.fontFamily, AppTheme.fontFamily);
      expect(theme.textTheme.headlineMedium?.fontFamily, AppTheme.fontFamily);
      expect(theme.textTheme.labelSmall?.fontFamily, AppTheme.fontFamily);
      expect(Directory('lib').listSync(recursive: true).whereType<File>().any(
            (f) => f.path.endsWith('.dart') && f.readAsStringSync().contains('google_fonts'),
          ), isFalse);
    });
  });

  group('parchment', () {
    test('the app background is exactly #F9F6F0, flat', () {
      expect(AppColors.parchmentLight, const Color(0xFFF9F6F0));
      expect(AppTheme.light.scaffoldBackgroundColor, const Color(0xFFF9F6F0));
      final sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.readAsStringSync())
          .join('\n');
      expect(sources.contains('parchmentRadialGradient'), isFalse, reason: 'background is one flat colour');
      expect(sources.contains('parchmentDark'), isFalse);
    });
  });

  group('no placeholder controls', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    test('no social sign-in or licence-purchase stubs ship', () {
      expect(sources.contains('sign-in is coming soon'), isFalse);
      expect(sources.contains('_SocialSignInRow'), isFalse);
      expect(sources.contains('Purchase Additional Licenses'), isFalse);
      expect(sources.toLowerCase().contains('coming soon'), isFalse);
    });
  });
}
