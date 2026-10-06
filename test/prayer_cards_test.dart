import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/prayer_item.dart';
import 'package:trellis/services/prayer_photo_service.dart';
import 'package:trellis/theme/app_theme.dart';
import 'package:trellis/widgets/brass_glyph.dart';
import 'package:trellis/widgets/prayer_card.dart';
import 'package:trellis/widgets/prayer_garden_field.dart';
import 'package:trellis/widgets/prayer_medallion.dart';
import 'package:trellis/widgets/prayer_photo_row.dart';
import 'package:trellis/widgets/trimmed_asset.dart';

/// A valid 1x1 PNG — the smallest thing the image decoder will accept.
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Bytes that open like a JPEG (the picker's usual output), padded to [length].
Uint8List _jpegLike([int length = 64]) =>
    Uint8List(length)..setAll(0, const [0xFF, 0xD8, 0xFF, 0xE0]);

Map<String, dynamic> _row({Map<String, dynamic> extra = const {}}) => {
      'id': 'p1',
      'category': 'people',
      'title': 'Maria Lopez',
      'details': 'Recovering from surgery.',
      'phone_number': null,
      'scripture': 'Philippians 4:6-7',
      'share_with_witnesses': false,
      'is_answered': false,
      'last_prayed_date': '2026-10-04',
      'answered_date': null,
      ...extra,
    };

/// The app's theme around [child], centred, as the screens would host it.
Widget _host(Widget child, {double textScale = 1}) => MaterialApp(
      theme: AppTheme.light,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: app!,
      ),
      home: Scaffold(body: Center(child: child)),
    );

void _useScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

bool _isPlant(Widget widget, String name) =>
    widget is TrimmedAsset && widget.asset == 'assets/images/$name.png';

Finder _plants(String name) => find.byWidgetPredicate((w) => _isPlant(w, name));

void main() {
  group('PrayerItem', () {
    test('reads a row from a database that has no photo_path column yet', () {
      final item = PrayerItem.fromRow(_row());
      expect(item.title, 'Maria Lopez');
      expect(item.photoPath, isNull);
    });

    test('reads the photo path when there is one', () {
      final item = PrayerItem.fromRow(_row(extra: {'photo_path': 'user-1/p1.jpg'}));
      expect(item.photoPath, 'user-1/p1.jpg');
    });

    test('a null, blank or malformed photo_path is simply "no photo"', () {
      expect(PrayerItem.fromRow(_row(extra: {'photo_path': null})).photoPath, isNull);
      expect(PrayerItem.fromRow(_row(extra: {'photo_path': '  '})).photoPath, isNull);
      expect(PrayerItem.fromRow(_row(extra: {'photo_path': 42})).photoPath, isNull);
    });

    test('a new prayer is inserted without a photo_path', () {
      final item = PrayerItem.fromRow(_row(extra: {'photo_path': 'user-1/p1.jpg'}));
      expect(item.toInsertRow('user-1').containsKey('photo_path'), isFalse);
    });

    test("a photo is stored in the owner's own folder, named for the prayer", () {
      expect(prayerPhotoPathFor(userId: 'user-1', prayerId: 'p1'), 'user-1/p1.jpg');
      expect(prayerPhotoBucket, 'prayer-photos');
    });
  });

  group('PrayerPhotoService links', () {
    late DateTime now;
    late int requests;

    PrayerPhotoService service({Future<String> Function(String path, int seconds)? signer}) {
      return PrayerPhotoService(
        clock: () => now,
        signer: signer ??
            (path, seconds) async {
              requests++;
              return 'https://example.test/$path?request=$requests';
            },
      );
    }

    setUp(() {
      now = DateTime(2026, 10, 5, 9);
      requests = 0;
    });

    test('hands back the cached link until shortly before it expires, then asks again', () async {
      final photos = service();

      expect(photos.cachedUrlFor('u/a.jpg'), isNull);
      final first = await photos.urlFor('u/a.jpg');
      expect(first, 'https://example.test/u/a.jpg?request=1');
      expect(await photos.urlFor('u/a.jpg'), first);
      expect(photos.cachedUrlFor('u/a.jpg'), first);
      expect(requests, 1);

      // Still inside the link's life, less the safety margin.
      now = now.add(
        PrayerPhotoService.linkLifetime -
            PrayerPhotoService.refreshMargin -
            const Duration(seconds: 1),
      );
      expect(await photos.urlFor('u/a.jpg'), first);
      expect(requests, 1);

      // Past the margin: the old link is retired and a fresh one fetched.
      now = now.add(const Duration(seconds: 2));
      expect(photos.cachedUrlFor('u/a.jpg'), isNull);
      expect(await photos.urlFor('u/a.jpg'), 'https://example.test/u/a.jpg?request=2');
      expect(requests, 2);
    });

    test('asks for the lifetime it caches by, and keeps paths apart', () async {
      int? askedFor;
      final photos = service(signer: (path, seconds) async {
        askedFor = seconds;
        return 'link:$path';
      });
      expect(await photos.urlFor('u/a.jpg'), 'link:u/a.jpg');
      expect(await photos.urlFor('u/b.jpg'), 'link:u/b.jpg');
      expect(askedFor, PrayerPhotoService.linkLifetime.inSeconds);
    });

    test('a list asking for the same photo at once makes one request', () async {
      final gate = Completer<String>();
      final photos = service(signer: (path, seconds) {
        requests++;
        return gate.future;
      });

      final all = [for (var i = 0; i < 30; i++) photos.urlFor('u/a.jpg')];
      gate.complete('link');
      expect(await Future.wait(all), everyElement('link'));
      expect(requests, 1);
    });

    test('invalidating one path fetches a new link for it and tells listeners', () async {
      final photos = service();
      var notified = 0;
      photos.addListener(() => notified++);

      await photos.urlFor('u/a.jpg');
      await photos.urlFor('u/b.jpg');
      expect(requests, 2);

      photos.invalidate('u/a.jpg');
      expect(notified, 1);
      expect(photos.cachedUrlFor('u/a.jpg'), isNull);
      expect(photos.cachedUrlFor('u/b.jpg'), isNotNull);

      await photos.urlFor('u/a.jpg');
      await photos.urlFor('u/b.jpg');
      expect(requests, 3);
    });

    test('a link requested before an invalidation is not cached after it', () async {
      final gate = Completer<String>();
      final photos = service(signer: (path, seconds) {
        requests++;
        return requests == 1 ? gate.future : Future.value('new');
      });

      final stale = photos.urlFor('u/a.jpg');
      photos.invalidate('u/a.jpg');
      gate.complete('old');
      await stale;

      expect(photos.cachedUrlFor('u/a.jpg'), isNull);
      expect(await photos.urlFor('u/a.jpg'), 'new');
    });

    test('a failure yields null, is not retried at once, and is retried later', () async {
      var failing = true;
      final photos = service(signer: (path, seconds) async {
        requests++;
        if (failing) throw StateError('bucket not found');
        return 'link';
      });

      expect(await photos.urlFor('u/a.jpg'), isNull);
      expect(await photos.urlFor('u/a.jpg'), isNull);
      expect(requests, 1, reason: 'a failing garden must not hammer the server');

      failing = false;
      now = now.add(PrayerPhotoService.retryAfterFailure);
      expect(await photos.urlFor('u/a.jpg'), 'link');
      expect(requests, 2);
    });
  });

  group('PrayerPhotoService storing', () {
    test('uploads to <user id>/<prayer id>.jpg and shows the new photo from memory', () async {
      final uploads = <String, Uint8List>{};
      final photos = PrayerPhotoService(
        currentUserId: () => 'user-1',
        uploader: (path, bytes) async => uploads[path] = bytes,
        signer: (path, seconds) async => 'link-${uploads.length}',
      );
      var notified = 0;
      photos.addListener(() => notified++);
      await photos.urlFor('user-1/p1.jpg');

      final bytes = _jpegLike();
      final path = await photos.upload(prayerId: 'p1', bytes: bytes);

      expect(path, 'user-1/p1.jpg');
      expect(uploads[path], same(bytes));
      expect(photos.bytesFor(path), same(bytes));
      expect(photos.cachedUrlFor(path), isNull, reason: 'the old link showed the old photo');
      expect(notified, 1);
    });

    test('a failed upload throws and remembers nothing', () async {
      final photos = PrayerPhotoService(
        currentUserId: () => 'user-1',
        uploader: (path, bytes) async => throw StateError('offline'),
      );
      await expectLater(
        photos.upload(prayerId: 'p1', bytes: _jpegLike()),
        throwsStateError,
      );
      expect(photos.bytesFor('user-1/p1.jpg'), isNull);
    });

    test('nobody signed in: refuses rather than uploading somewhere wrong', () async {
      var uploaded = false;
      final photos = PrayerPhotoService(
        currentUserId: () => null,
        uploader: (path, bytes) async => uploaded = true,
      );
      await expectLater(photos.upload(prayerId: 'p1', bytes: _jpegLike()), throwsStateError);
      expect(uploaded, isFalse);
    });

    test('removing never throws, and forgets the photo either way', () async {
      final removed = <String>[];
      var failing = false;
      final photos = PrayerPhotoService(
        currentUserId: () => 'user-1',
        uploader: (path, bytes) async {},
        remover: (path) async {
          if (failing) throw StateError('offline');
          removed.add(path);
        },
        signer: (path, seconds) async => 'link',
      );

      final path = await photos.upload(prayerId: 'p1', bytes: _jpegLike());
      expect(await photos.remove(path), isTrue);
      expect(removed, [path]);
      expect(photos.bytesFor(path), isNull);

      failing = true;
      await photos.urlFor(path);
      expect(await photos.remove(path), isFalse);
      expect(photos.cachedUrlFor(path), isNull);
    });
  });

  group('PrayerPhotoService choosing', () {
    test('a chosen JPEG comes back ready to use', () async {
      final bytes = _jpegLike();
      final pick = await PrayerPhotoService(picker: () async => bytes).pick();
      expect(pick.status, PrayerPhotoPickStatus.picked);
      expect(pick.bytes, same(bytes));
      expect(pick.notice, isNull);
    });

    test('backing out of the picker is not an error', () async {
      final pick = await PrayerPhotoService(picker: () async => null).pick();
      expect(pick.status, PrayerPhotoPickStatus.cancelled);
      expect(pick.bytes, isNull);
      expect(pick.notice, isNull);
    });

    test('a photo over 5 MB is turned away with a clear notice', () async {
      final big = _jpegLike(PrayerPhotoService.maxBytes + 1);
      final pick = await PrayerPhotoService(picker: () async => big).pick();
      expect(pick.status, PrayerPhotoPickStatus.tooLarge);
      expect(pick.bytes, isNull);
      expect(pick.notice, contains('5 MB'));
      // Exactly at the limit is fine.
      expect(
        PrayerPhotoService.check(_jpegLike(PrayerPhotoService.maxBytes)).status,
        PrayerPhotoPickStatus.picked,
      );
    });

    test('PNG, GIF and WebP are accepted; anything else is not', () {
      expect(PrayerPhotoService.check(_tinyPng).status, PrayerPhotoPickStatus.picked);
      expect(
        PrayerPhotoService.check(Uint8List.fromList('GIF89a..........'.codeUnits)).status,
        PrayerPhotoPickStatus.picked,
      );
      expect(
        PrayerPhotoService.check(Uint8List.fromList('RIFF....WEBPVP8 '.codeUnits)).status,
        PrayerPhotoPickStatus.picked,
      );
      final unknown = PrayerPhotoService.check(Uint8List.fromList('....ftypheic....'.codeUnits));
      expect(unknown.status, PrayerPhotoPickStatus.unsupported);
      expect(unknown.notice, isNotNull);
      expect(PrayerPhotoService.check(Uint8List(0)).status, PrayerPhotoPickStatus.unsupported);
    });

    test('a picker that cannot open (e.g. access denied) is reported, not thrown', () async {
      final pick = await PrayerPhotoService(picker: () async => throw StateError('denied')).pick();
      expect(pick.status, PrayerPhotoPickStatus.unavailable);
      expect(pick.notice, isNotNull);
    });
  });

  group('PrayerMedallion', () {
    test('initials', () {
      expect(PrayerMedallion.initialsOf('Maria Lopez'), 'ML');
      expect(PrayerMedallion.initialsOf('  maria   de la   cruz '), 'MC');
      expect(PrayerMedallion.initialsOf('maria'), 'M');
      expect(PrayerMedallion.initialsOf('Élise'), 'É');
      expect(PrayerMedallion.initialsOf(''), '?');
      expect(PrayerMedallion.initialsOf('   '), '?');
    });

    test('a name that opens with an emoji is not cut mid-character', () {
      expect(PrayerMedallion.initialsOf('🌸 Maria'), '🌸M');
      // A family emoji is several code points joined together.
      expect(PrayerMedallion.initialsOf('👨‍👩‍👧 The Lopez Family'), '👨‍👩‍👧F');
    });

    testWidgets('shows initials in a ring of the requested size when there is no photo',
        (tester) async {
      await tester.pumpWidget(_host(const PrayerMedallion(name: 'Maria Lopez', size: 96)));
      expect(find.text('ML'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.getSize(find.byType(PrayerMedallion)), const Size(96, 96));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an emoji-leading name, small, at a large text size, does not throw',
        (tester) async {
      await tester.pumpWidget(
        _host(const PrayerMedallion(name: '🌸 Maria', size: 32), textScale: 1.3),
      );
      expect(find.text('🌸M'), findsOneWidget);
      expect(tester.getSize(find.byType(PrayerMedallion)), const Size(32, 32));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a situation shows its engraved mark instead of initials', (tester) async {
      await tester.pumpWidget(
        _host(const PrayerMedallion(name: 'The job search', glyph: BrassGlyphKind.mountain)),
      );
      expect(find.byType(BrassGlyph), findsOneWidget);
      expect(find.text('TS'), findsNothing);
    });

    testWidgets('a photo held in memory is drawn over the initials', (tester) async {
      await tester.pumpWidget(_host(PrayerMedallion(name: 'Maria Lopez', photoBytes: _tinyPng)));
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      // Still underneath, for the moment before the photo has decoded.
      expect(find.text('ML'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a stored photo that will not load leaves the initials showing', (tester) async {
      // The test binding answers every network request with an error, which
      // is exactly the case to survive: offline, or a link that has expired.
      var requests = 0;
      final photos = PrayerPhotoService(signer: (path, seconds) async {
        requests++;
        return 'https://example.test/$path';
      });
      Widget medallion() => _host(
            PrayerMedallion(name: 'Maria Lopez', photoPath: 'user-1/p1.jpg', service: photos),
          );

      await tester.pumpWidget(medallion());
      expect(find.text('ML'), findsOneWidget, reason: 'initials while the link is fetched');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('ML'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Rebuilding the list does not ask for the link again.
      await tester.pumpWidget(medallion());
      await tester.pump();
      expect(requests, 1);
    });

    testWidgets('no link available (bucket not set up yet): initials, no error', (tester) async {
      final photos = PrayerPhotoService(
        signer: (path, seconds) async => throw StateError('bucket not found'),
      );
      await tester.pumpWidget(_host(
        PrayerMedallion(name: 'Maria Lopez', photoPath: 'user-1/p1.jpg', service: photos),
      ));
      await tester.pump();
      expect(find.text('ML'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('PrayerPhotoRow', () {
    testWidgets('offers Add Photo, and says who can see it', (tester) async {
      var picks = 0;
      await tester.pumpWidget(_host(SizedBox(
        width: 212, // a dialog's inner width on a 320-wide phone
        child: PrayerPhotoRow(name: 'Maria Lopez', onPick: () => picks++, onRemove: () {}),
      )));

      expect(find.text('ML'), findsOneWidget);
      expect(find.text('Photos are private to you.'), findsOneWidget);
      expect(find.text('Change'), findsNothing);
      expect(find.text('Remove'), findsNothing);
      await tester.tap(find.text('Add Photo'));
      expect(picks, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with a photo: Change and Remove, without overflowing a narrow dialog',
        (tester) async {
      var picks = 0;
      var removes = 0;
      await tester.pumpWidget(_host(
        SizedBox(
          width: 212,
          child: PrayerPhotoRow(
            name: 'Maria Lopez',
            photoBytes: _tinyPng,
            onPick: () => picks++,
            onRemove: () => removes++,
          ),
        ),
        textScale: 1.3,
      ));

      expect(find.text('Add Photo'), findsNothing);
      await tester.tap(find.text('Change'));
      await tester.tap(find.text('Remove'));
      expect((picks, removes), (1, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('while saving, the actions give way to a spinner', (tester) async {
      await tester.pumpWidget(_host(SizedBox(
        width: 212,
        child: PrayerPhotoRow(name: 'Maria', busy: true, onPick: () {}, onRemove: () {}),
      )));
      expect(find.text('Add Photo'), findsNothing);
      expect(find.bySemanticsLabel('Saving photo'), findsOneWidget);
    });
  });

  group('layoutGardenPlots', () {
    const fieldHeight = 220.0;

    test('every plot stays inside the field and none overlap, at any width and count', () {
      for (final width in [250.0, 272.0, 320.0, 375.0, 440.0, 600.0, 900.0]) {
        final size = Size(width, fieldHeight);
        final field = Offset.zero & size;
        for (var count = 1; count <= gardenFieldMaxPlots; count++) {
          final plots = layoutGardenPlots(size, count);
          expect(plots, hasLength(count));
          for (var i = 0; i < plots.length; i++) {
            final cell = plots[i].cell;
            final reason = '$count plots in ${width.toInt()}px, plot $i: $cell';
            expect(cell.left, greaterThanOrEqualTo(field.left - 0.001), reason: reason);
            expect(cell.right, lessThanOrEqualTo(field.right + 0.001), reason: reason);
            expect(cell.top, greaterThanOrEqualTo(field.top - 0.001), reason: reason);
            expect(cell.bottom, lessThanOrEqualTo(field.bottom + 0.001), reason: reason);
            expect(plots[i].plantHeight, lessThanOrEqualTo(cell.height + 0.001), reason: reason);
            for (var j = i + 1; j < plots.length; j++) {
              final shared = cell.intersect(plots[j].cell);
              final overlaps = shared.width > 0.001 && shared.height > 0.001;
              expect(overlaps, isFalse, reason: 'plots $i and $j overlap ($reason)');
            }
          }
        }
      }
    });

    test('one to three plants are full size; a dozen are smaller, in rows', () {
      const size = Size(320, fieldHeight);
      for (var count = 1; count <= 3; count++) {
        final plots = layoutGardenPlots(size, count);
        expect(plots.map((p) => p.plantHeight), everyElement(80.0));
        expect(plots.map((p) => p.cell.top).toSet(), hasLength(1), reason: 'one row');
      }

      final dozen = layoutGardenPlots(size, 12);
      final rows = dozen.map((p) => p.cell.top).toSet();
      expect(rows.length, inInclusiveRange(2, 3));
      expect(dozen.map((p) => p.plantHeight), everyElement(lessThan(80.0)));
      // Back rows are no bigger than the rows in front of them.
      for (var i = 1; i < dozen.length; i++) {
        expect(dozen[i].plantHeight, greaterThanOrEqualTo(dozen[i - 1].plantHeight));
      }
    });

    test('a full field keeps every plot a comfortable tap target on any phone', () {
      for (final width in [272.0, 320.0, 375.0, 440.0]) {
        final size = Size(width, fieldHeight);
        expect(gardenFieldCapacity(size), gardenFieldMaxPlots);
        for (final plot in layoutGardenPlots(size, gardenFieldMaxPlots)) {
          expect(plot.cell.width, greaterThanOrEqualTo(44));
          expect(plot.cell.height, greaterThanOrEqualTo(44));
        }
      }
    });

    test('a field too small for a dozen offers fewer plots rather than tiny ones', () {
      const cramped = Size(150, fieldHeight);
      final capacity = gardenFieldCapacity(cramped);
      expect(capacity, inInclusiveRange(1, gardenFieldMaxPlots - 1));
      for (final plot in layoutGardenPlots(cramped, capacity)) {
        expect(plot.cell.width, greaterThanOrEqualTo(44));
      }
      expect(layoutGardenPlots(cramped, 0), isEmpty);
    });
  });

  group('PrayerGardenField', () {
    List<GardenEntry> entries(int count) => [
          for (var i = 0; i < count; i++)
            GardenEntry(id: 'p$i', title: 'Prayer $i', details: 'Details for prayer $i'),
        ];

    Widget field(double width, int count, {bool answered = false}) => _host(
          SizedBox(
            width: width,
            child: PrayerGardenField(entries: entries(count), answered: answered),
          ),
        );

    for (final width in [320.0, 440.0]) {
      for (final count in [1, 6, 12, 13, 40]) {
        testWidgets('$count prayers fit in a ${width.toInt()}px field', (tester) async {
          await tester.pumpWidget(field(width, count));
          expect(tester.takeException(), isNull);

          final expectedPlants = count <= 12 ? count : 11;
          expect(_plants('prayer_sprout'), findsNWidgets(expectedPlants));
          if (count <= 12) {
            expect(find.textContaining('+'), findsNothing);
          } else {
            expect(find.text('+${count - 11}'), findsOneWidget);
          }

          // Nothing is laid out beyond the field's edges, and every plant
          // keeps a full-size tap target and its spoken name.
          final bounds = tester.getRect(find.byType(PrayerGardenField));
          expect(bounds.size, Size(width, 220));
          for (var i = 0; i < expectedPlants; i++) {
            final target = tester.getRect(find.bySemanticsLabel('Prayer $i'));
            expect(bounds.contains(target.topLeft), isTrue, reason: 'plant $i: $target');
            expect(
              target.right <= bounds.right + 0.001 && target.bottom <= bounds.bottom + 0.001,
              isTrue,
              reason: 'plant $i: $target',
            );
            expect(target.width, greaterThanOrEqualTo(44));
            expect(target.height, greaterThanOrEqualTo(44));
          }
          for (final plant in tester.widgetList(_plants('prayer_sprout'))) {
            final drawn = tester.getRect(find.byWidget(plant));
            expect(bounds.expandToInclude(drawn), bounds, reason: 'plant drawn at $drawn');
          }
        });
      }
    }

    testWidgets('answered prayers bloom, laid out the same way', (tester) async {
      await tester.pumpWidget(field(320, 14, answered: true));
      expect(tester.takeException(), isNull);
      expect(_plants('prayer_bloom'), findsNWidgets(11));
      expect(_plants('prayer_sprout'), findsNothing);
      expect(find.text('+3'), findsOneWidget);
    });

    testWidgets('an empty garden is just the field', (tester) async {
      await tester.pumpWidget(field(320, 0));
      expect(tester.takeException(), isNull);
      expect(_plants('prayer_sprout'), findsNothing);
      expect(_plants('prayer_field'), findsOneWidget);
    });

    testWidgets('holds together at a large text size', (tester) async {
      await tester.pumpWidget(_host(
        SizedBox(
          width: 320,
          child: PrayerGardenField(entries: entries(140), answered: false),
        ),
        textScale: 1.3,
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('+129'), findsOneWidget);
    });

    testWidgets('tapping a plant opens that prayer', (tester) async {
      await tester.pumpWidget(field(320, 12));
      await tester.tap(find.bySemanticsLabel('Prayer 7'));
      await tester.pumpAndSettle();
      expect(find.text('Prayer 7'), findsOneWidget);
      expect(find.text('Details for prayer 7'), findsOneWidget);
    });

    testWidgets('a screen can open its own detail instead', (tester) async {
      final opened = <String?>[];
      await tester.pumpWidget(_host(SizedBox(
        width: 320,
        child: PrayerGardenField(
          entries: entries(13),
          answered: false,
          onEntryTap: (entry) => opened.add(entry.id),
        ),
      )));
      await tester.tap(find.bySemanticsLabel('Prayer 10'));
      await tester.pumpAndSettle();
      expect(opened, ['p10']);
      expect(find.text('Details for prayer 10'), findsNothing);
    });

    testWidgets('the +N marker says where the rest are', (tester) async {
      await tester.pumpWidget(field(320, 13));
      final marker = find.bySemanticsLabel('2 more, listed below');
      expect(marker, findsOneWidget);
      expect(tester.getSize(marker).shortestSide, greaterThanOrEqualTo(44));

      await tester.tap(find.text('+2'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('All 13 are listed below.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // let the notice's timer finish
    });

    testWidgets('…or hands the tap to the screen, to scroll to its list', (tester) async {
      var shown = 0;
      await tester.pumpWidget(_host(SizedBox(
        width: 440,
        child: PrayerGardenField(
          entries: entries(20),
          answered: false,
          onShowAll: () => shown++,
        ),
      )));
      await tester.tap(find.text('+9'));
      await tester.pump();
      expect(shown, 1);
      expect(find.textContaining('listed below'), findsNothing);
    });
  });

  group('PrayerCard', () {
    final today = DateTime(2026, 10, 5);
    final longDetails = List.filled(
      12,
      'Recovering from surgery and waiting on results; pray for patience, for her '
          'family, and for the doctors who are caring for her.',
    ).join(' ');

    PrayerItem person({String details = 'Knee surgery.', DateTime? lastPrayed}) =>
        PrayerItem(
          id: 'p1',
          category: PrayerCategory.people,
          title: 'Maria Lopez',
          details: details,
          scripture: 'Philippians 4:6-7',
          lastPrayedDate: lastPrayed,
        );

    test('the last-prayed line', () {
      expect(PrayerCard.lastPrayedLine(null, today), 'First time praying for this');
      expect(PrayerCard.lastPrayedLine(DateTime(2026, 10, 5, 7), today), 'Last prayed today');
      expect(PrayerCard.lastPrayedLine(DateTime(2026, 10, 4, 23), today), 'Last prayed yesterday');
      expect(PrayerCard.lastPrayedLine(DateTime(2026, 10, 2), today), 'Last prayed 3 days ago');
      expect(PrayerCard.lastPrayedLine(DateTime(2026, 9, 12), today), 'Last prayed Sep 12');
      expect(PrayerCard.lastPrayedLine(DateTime(2025, 12, 25), today), 'Last prayed Dec 25, 2025');
    });

    testWidgets('a short prayer: medallion, heading, name, details, scripture, last prayed',
        (tester) async {
      _useScreen(tester, const Size(375, 667));
      await tester.pumpWidget(_host(SizedBox(
        width: 327,
        height: 347,
        child: PrayerCard(item: person(lastPrayed: DateTime(2026, 10, 4)), today: today),
      )));

      expect(tester.takeException(), isNull);
      expect(find.byType(PrayerMedallion), findsOneWidget);
      expect(find.text('ML'), findsOneWidget);
      expect(find.text('PERSON'), findsNothing);
      expect(find.text('Maria Lopez'), findsOneWidget);
      expect(find.text('Knee surgery.'), findsOneWidget);
      expect(find.text('Philippians 4:6-7'), findsOneWidget);
      expect(find.text('Last prayed yesterday'), findsOneWidget);

      // Balanced in the frame: about as much room above the medallion as
      // below the last line, not everything pushed to one end.
      final card = tester.getRect(find.byType(PrayerCard));
      final above = tester.getRect(find.byType(PrayerMedallion)).top - card.top;
      final below = card.bottom - tester.getRect(find.text('Last prayed yesterday')).bottom;
      expect((above - below).abs(), lessThan(2));
    });

    testWidgets('long details at a large text size scroll inside the card (375x667)',
        (tester) async {
      _useScreen(tester, const Size(375, 667));
      await tester.pumpWidget(_host(
        SizedBox(
          width: 327,
          height: 347,
          child: PrayerCard(item: person(details: longDetails), today: today),
        ),
        textScale: 1.3,
      ));

      expect(tester.takeException(), isNull, reason: 'nothing overflows the card');
      expect(tester.getSize(find.byType(PrayerCard)), const Size(327, 347));

      // The foot of the card is below the fold to begin with, and reachable.
      final card = tester.getRect(find.byType(PrayerCard));
      final lastLine = find.text('First time praying for this');
      expect(tester.getRect(lastLine).top, greaterThan(card.bottom));
      await tester.drag(find.byType(PrayerCard), const Offset(0, -5000));
      await tester.pumpAndSettle();
      expect(tester.getRect(lastLine).bottom, lessThanOrEqualTo(card.bottom));
      expect(find.text('Philippians 4:6-7'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('holds together on a tall phone and for a long title (440x956)', (tester) async {
      _useScreen(tester, const Size(440, 956));
      final item = PrayerItem(
        id: 's1',
        category: PrayerCategory.situations,
        title: 'The long search for a new job after the plant closed down last spring',
      );
      for (final scale in [1.0, 1.3]) {
        await tester.pumpWidget(_host(
          SizedBox(width: 340, height: 440, child: PrayerCard(item: item, today: today)),
          textScale: scale,
        ));
        expect(tester.takeException(), isNull);
      }
      // No "SITUATION" / "PERSON" kicker over the name any more.
      expect(find.text('SITUATION'), findsNothing);
      // A situation has the category's mark in the medallion, not initials.
      expect(
        find.descendant(of: find.byType(PrayerMedallion), matching: find.byType(BrassGlyph)),
        findsOneWidget,
      );
      expect(find.text('First time praying for this'), findsOneWidget);
    });

    testWidgets('a waiting card behind the top one is drawn faded', (tester) async {
      await tester.pumpWidget(_host(SizedBox(
        width: 300,
        height: 340,
        child: PrayerCard(item: person(), faded: true, today: today),
      )));
      final opacity = tester.widget<Opacity>(
        find.descendant(of: find.byType(PrayerCard), matching: find.byType(Opacity)).first,
      );
      expect(opacity.opacity, 0.5);
    });
  });
}
