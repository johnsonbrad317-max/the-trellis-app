import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/runner_profile.dart';
import 'package:trellis/models/witness_notice.dart';
import 'package:trellis/screens/witness_shell.dart';
import 'package:trellis/theme/app_theme.dart';
import 'package:trellis/widgets/departure_notice.dart';

/// A Witness is told, once, when a Runner they walk with deletes their account
/// (028_departure_notices.sql + delete-account + the Witness shell).
void main() {
  WitnessNotice notice({String id = 'n1', String name = 'Sarah'}) => WitnessNotice(
        id: id,
        kind: WitnessNoticeKind.runnerLeft,
        runnerFirstName: name,
        createdAt: DateTime.utc(2026, 10, 7, 12),
      );

  group('WitnessNotice', () {
    test('reads a get_my_witness_notices row', () {
      final parsed = WitnessNotice.fromRow({
        'id': 'abc',
        'kind': 'runner_left',
        'runner_first_name': 'Sarah',
        'created_at': '2026-10-07T12:00:00+00:00',
      })!;
      expect(parsed.id, 'abc');
      expect(parsed.kind, WitnessNoticeKind.runnerLeft);
      expect(parsed.runnerFirstName, 'Sarah');
      expect(parsed.createdAt, DateTime.utc(2026, 10, 7, 12));
    });

    test('ignores a kind this build does not know, or a row without an id', () {
      expect(WitnessNotice.fromRow({'id': 'abc', 'kind': 'something_new'}), isNull);
      expect(WitnessNotice.fromRow({'kind': 'runner_left', 'runner_first_name': 'Sarah'}), isNull);
    });

    test('a blank name reads as "Your Runner", like the server', () {
      final parsed = WitnessNotice.fromRow({'id': 'abc', 'kind': 'runner_left', 'runner_first_name': ' '})!;
      expect(parsed.runnerFirstName, WitnessNotice.fallbackFirstName);
      expect(parsed.title, 'Your Runner has left The Trellis');
    });

    test('the copy', () {
      final n = notice();
      expect(n.title, 'Sarah has left The Trellis');
      expect(
        n.message,
        'Sarah deleted their account, so everything they shared — their Rule of '
        'Life, check-ins and prayers — was removed with it, and they no longer '
        'appear here. You might reach out to them directly.',
      );
    });
  });

  group('the dialog', () {
    testWidgets('is a bookplate with the copy and a single OK', (tester) async {
      var closed = false;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: GestureDetector(
                onTap: () async {
                  await showDepartureNoticeDialog(context, notice());
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Sarah has left The Trellis'), findsOneWidget);
      expect(find.textContaining('You might reach out to them directly.'), findsOneWidget);
      expect(find.textContaining('Nothing you did'), findsNothing);
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      // Hand-built: no stock Material dialog, buttons or icons.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(Icon), findsNothing);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Sarah has left The Trellis'), findsNothing);
      expect(closed, isTrue);
    });
  });

  group('a preview profile', () {
    test('never reports a pending note', () {
      final profile = RunnerProfile.preview()..debugAddWitnessNotice(notice());
      expect(profile.isPreview, isTrue);
      expect(profile.pendingWitnessNotices, isEmpty);
    });

    testWidgets('shows nothing, even when asked directly', (tester) async {
      final profile = RunnerProfile.preview()..debugAddWitnessNotice(notice());
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: GestureDetector(
                onTap: () => showPendingDepartureNotices(context, profile),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('has left The Trellis'), findsNothing);
    });

    testWidgets('the Witness shell shows nothing', (tester) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final profile = RunnerProfile.preview()..debugAddWitnessNotice(notice());
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: WitnessShell(profile: profile)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('has left The Trellis'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('names shared with the server', () {
    String read(String path) => File(path).readAsStringSync();

    test('028 defines what the app calls', () {
      final sql = read('supabase/migrations/028_departure_notices.sql');
      expect(sql, contains('function public.get_my_witness_notices()'));
      expect(sql, contains('function public.mark_witness_notice_seen(p_id uuid)'));
      expect(sql, contains("check (kind in ('runner_left'))"));
      expect(sql, contains("'Your Runner'"));
      expect(WitnessNotice.fallbackFirstName, 'Your Runner');
    });

    test('delete-account writes the note before it deletes the account', () {
      final fn = read('supabase/functions/delete-account/index.ts');
      final record = fn.indexOf("callDepartureRpc(admin, 'record_runner_departure'");
      final delete = fn.indexOf('admin.auth.admin.deleteUser(userId)');
      expect(record, greaterThan(0));
      expect(delete, greaterThan(record));
    });

    test('no client reads last-seen (026 and 028 keep it private)', () {
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final source = file.readAsStringSync()
            .split('\n')
            .where((line) => !line.trimLeft().startsWith('//'))
            .join('\n');
        expect(source, isNot(contains('last_seen_at')), reason: file.path);
        expect(source, isNot(contains('app_removed_at')), reason: file.path);
      }
      expect(read('supabase/migrations/026_witness_nudges.sql'),
          isNot(contains('grant select (last_seen_at, app_removed_at)')));
    });
  });
}
