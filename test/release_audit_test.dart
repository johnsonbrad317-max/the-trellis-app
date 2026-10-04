import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/firebase_options.dart';
import 'package:trellis/models/rule_item.dart';
import 'package:trellis/models/rule_of_life_baseline.dart';
import 'package:trellis/models/watched_runner.dart';
import 'package:trellis/theme/app_colors.dart';
import 'package:trellis/theme/app_theme.dart';

/// Guards for defects found in the 1.0 pre-release audit, so they can't return.
void main() {
  _modelTests();
  _phase5Tests();
  _firebaseConsistencyTests();

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

// ---------------------------------------------------------------------------
// Firebase / bundle identifier consistency
// ---------------------------------------------------------------------------
void _firebaseConsistencyTests() {
  const bundleId = 'com.unhinderedlives.trellis';

  String plistValue(String plist, String key) {
    final match = RegExp('<key>$key</key>${r'\s*'}<string>([^<]*)</string>').firstMatch(plist);
    expect(match, isNotNull, reason: '$key missing from GoogleService-Info.plist');
    return match!.group(1)!;
  }

  group('Firebase configuration', () {
    test('the iOS plist, firebase_options.dart and the Xcode project agree', () {
      final plist = File('ios/Runner/GoogleService-Info.plist').readAsStringSync();
      final ios = DefaultFirebaseOptions.ios;
      expect(plistValue(plist, 'BUNDLE_ID'), bundleId);
      expect(plistValue(plist, 'GOOGLE_APP_ID'), ios.appId);
      expect(plistValue(plist, 'API_KEY'), ios.apiKey);
      expect(plistValue(plist, 'GCM_SENDER_ID'), ios.messagingSenderId);
      expect(plistValue(plist, 'PROJECT_ID'), ios.projectId);
      expect(plistValue(plist, 'STORAGE_BUCKET'), ios.storageBucket);
      expect(ios.iosBundleId, bundleId);

      final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      final ids = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);')
          .allMatches(pbxproj)
          .map((m) => m.group(1)!)
          .toSet();
      expect(ids, {bundleId, '$bundleId.RunnerTests'});
    });

    test('the Android JSON, firebase_options.dart and Gradle agree', () {
      // The file may also list the previous registration (Firebase keeps it
      // until it is deleted in the console); only this app's entry matters.
      final clients = (jsonDecode(File('android/app/google-services.json').readAsStringSync())
          as Map<String, dynamic>)['client'] as List<dynamic>;
      final mine = clients.cast<Map<String, dynamic>>().where(
            (c) => c['client_info']['android_client_info']['package_name'] == bundleId,
          );
      expect(mine, hasLength(1), reason: 'exactly one client for $bundleId');
      final android = DefaultFirebaseOptions.android;
      expect(mine.single['client_info']['mobilesdk_app_id'], android.appId);
      expect(mine.single['api_key'][0]['current_key'], android.apiKey);

      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('applicationId = "$bundleId"'));
      expect(gradle, contains('namespace = "$bundleId"'));
      expect(
        File('android/app/src/main/kotlin/com/unhinderedlives/trellis/MainActivity.kt')
            .readAsStringSync(),
        startsWith('package $bundleId'),
      );
    });

    test('the old bundle identifier is gone everywhere', () {
      final offenders = <String>[];
      for (final entity in Directory('.').listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (path.contains('/build/') ||
            path.contains('/.dart_tool/') ||
            path.contains('/.git/') ||
            path.contains('/node_modules/') ||
            !RegExp(r'\.(dart|kt|kts|gradle|json|plist|pbxproj|yaml|md|xml|xcconfig|txt)$')
                .hasMatch(path)) {
          continue;
        }
        // This file, the checklist (which describes the migration) and
        // google-services.json (Firebase lists the previous registration there
        // until it is deleted in the console) may legitimately name it.
        if (path.endsWith('release_audit_test.dart') ||
            path.endsWith('RELEASE_CHECKLIST.md') ||
            path.endsWith('android/app/google-services.json')) {
          continue;
        }
        if (entity.readAsStringSync().contains('com.usengineering')) offenders.add(path);
      }
      expect(offenders, isEmpty);
    });
  });
}
