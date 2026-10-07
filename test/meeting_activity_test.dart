import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:trellis/models/meeting_activity.dart';
import 'package:trellis/models/shared_free_windows.dart';
import 'package:trellis/services/meeting_spot_service.dart';
import 'package:trellis/services/places_service.dart';

/// Coffee / lunch / Organic Life: which times are offered, on which days,
/// filtered by both people's busy blocks — and the Places API plumbing for
/// the midway spot. October 2026: Mon 12, Wed 14, Fri 16, Sat 17, Mon 19.
void main() {
  String hm(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
  List<String> dayLabels(List<MeetingDaySlots> days) =>
      [for (final d in days) '${d.day.month}/${d.day.day}'];

  group('MeetingActivity', () {
    test('coffee and lunch are their own kinds; every other chip is Organic Life', () {
      expect(MeetingActivity.coffee.kind, MeetingKind.coffee);
      expect(MeetingActivity.lunch.kind, MeetingKind.lunch);
      for (final organic in MeetingActivity.organicLifeOptions) {
        expect(organic.kind, MeetingKind.organicLife);
        expect(organic.isOrganicLife, isTrue);
      }
      expect(MeetingActivity.organicLifeOptions.map((a) => a.chipLabel),
          ['Errands', "Kids' Sports", 'House Project', 'Grilling/BBQ', 'Other']);
    });

    test('the fixed candidate times and an hour each', () {
      expect(MeetingKind.coffee.candidateTimes.map((t) => '${t.hour}:${t.minute}'),
          ['6:0', '6:30', '7:0', '7:30', '8:0']);
      expect(MeetingKind.lunch.candidateTimes.map((t) => '${t.hour}:${t.minute}'),
          ['11:0', '11:30', '12:0', '12:30']);
      expect(MeetingKind.organicLife.candidateTimes, isEmpty);
      expect(MeetingKind.coffee.durationMinutes, 60);
      expect(MeetingKind.lunch.durationMinutes, 60);
      expect(MeetingKind.organicLife.suggestsTimes, isFalse);
      expect(MeetingKind.organicLife.suggestsPlace, isFalse);
    });
  });

  group('candidateMeetingDays', () {
    test('coffee: the next five weekdays from 48 hours out, 6:00 to 8:00', () {
      final days = candidateMeetingDays(MeetingKind.coffee, now: DateTime(2026, 10, 12, 5));
      expect(dayLabels(days), ['10/14', '10/15', '10/16', '10/19', '10/20']);
      for (final day in days) {
        expect(day.starts.map(hm), ['6:00', '6:30', '7:00', '7:30', '8:00']);
        expect(day.day.weekday, lessThanOrEqualTo(DateTime.friday));
      }
    });

    test('lunch never yields a coffee time', () {
      final days = candidateMeetingDays(MeetingKind.lunch, now: DateTime(2026, 10, 12, 5));
      expect(days, hasLength(5));
      for (final day in days) {
        expect(day.starts.map(hm), ['11:00', '11:30', '12:00', '12:30']);
      }
      final all = [for (final d in days) ...d.starts];
      expect(all.where((t) => t.hour < 11), isEmpty);
    });

    test('Organic Life offers no times at all', () {
      expect(candidateMeetingDays(MeetingKind.organicLife, now: DateTime(2026, 10, 12, 5)), isEmpty);
      expect(
        suggestMeetingSlots(MeetingKind.organicLife, now: DateTime(2026, 10, 12, 5), busyA: const [], busyB: const []),
        isEmpty,
      );
    });

    test('a day whose times all fall inside the 48 hours is skipped (Friday → Monday)', () {
      // Wed 9:00 → earliest Fri 9:00: Friday's coffee hours are gone.
      final coffee = candidateMeetingDays(MeetingKind.coffee, now: DateTime(2026, 10, 14, 9));
      expect(dayLabels(coffee), ['10/19', '10/20', '10/21', '10/22', '10/23']);
      expect(coffee.first.day.weekday, DateTime.monday);
      // ...but Friday's lunch is still ahead.
      final lunch = candidateMeetingDays(MeetingKind.lunch, now: DateTime(2026, 10, 14, 9));
      expect(dayLabels(lunch), ['10/16', '10/19', '10/20', '10/21', '10/22']);
    });

    test('a window that starts on a Saturday begins on Monday', () {
      // Thu 10:00 → earliest Sat 10:00.
      final days = candidateMeetingDays(MeetingKind.coffee, now: DateTime(2026, 10, 15, 10));
      expect(dayLabels(days), ['10/19', '10/20', '10/21', '10/22', '10/23']);
      expect(days.every((d) => d.day.weekday != DateTime.saturday && d.day.weekday != DateTime.sunday),
          isTrue);
    });

    test('only the times at or after the earliest moment on the first day', () {
      final days = candidateMeetingDays(MeetingKind.coffee, now: DateTime(2026, 10, 12, 7, 15));
      expect(days.first.starts.map(hm), ['7:30', '8:00']);
      expect(days, hasLength(5));
    });

    test('emergency: what is left of today and tomorrow, weekends included', () {
      // Saturday 5:00 → earliest 7:00.
      final days = candidateMeetingDays(
        MeetingKind.coffee,
        now: DateTime(2026, 10, 17, 5),
        emergency: true,
      );
      expect(dayLabels(days), ['10/17', '10/18']);
      expect(days[0].starts.map(hm), ['7:00', '7:30', '8:00']);
      expect(days[1].starts.map(hm), ['6:00', '6:30', '7:00', '7:30', '8:00']);
    });

    test('emergency late at night: today is spent, tomorrow remains', () {
      final days = candidateMeetingDays(
        MeetingKind.lunch,
        now: DateTime(2026, 10, 16, 23),
        emergency: true,
      );
      expect(dayLabels(days), ['10/17']);
      expect(days.single.starts.map(hm), ['11:00', '11:30', '12:00', '12:30']);
    });
  });

  group('filterFreeForBoth', () {
    final now = DateTime(2026, 10, 12, 5); // first day Wed Oct 14
    DateTime wed(int h, [int m = 0]) => DateTime(2026, 10, 14, h, m);

    test('no calendars: the usual times come back unchecked', () {
      final candidates = candidateMeetingDays(MeetingKind.coffee, now: now);
      expect(
        filterFreeForBoth(candidates, durationMinutes: 60, busyA: null, busyB: const []),
        same(candidates),
      );
      expect(suggestMeetingSlots(MeetingKind.coffee, now: now).first.starts, hasLength(5));
    });

    test('a block covering only part of the hour rules that time out', () {
      final days = suggestMeetingSlots(
        MeetingKind.coffee,
        now: now,
        busyA: [TimeSpan(wed(6, 45), wed(7, 10))], // 6:00, 6:30 and 7:00 overlap it
        busyB: const [],
      );
      expect(days.first.day, DateTime(2026, 10, 14));
      expect(days.first.starts.map(hm), ['7:30', '8:00']);
      expect(days[1].starts, hasLength(5)); // Thursday untouched
    });

    test('both people count: their busy blocks combine', () {
      final days = suggestMeetingSlots(
        MeetingKind.coffee,
        now: now,
        busyA: [TimeSpan(wed(6, 45), wed(7, 10))],
        busyB: [TimeSpan(wed(8, 50), wed(9, 30))], // the last ten minutes of 8:00–9:00
      );
      expect(days.first.starts.map(hm), ['7:30']);
    });

    test('a block that only touches a meeting does not rule it out', () {
      final days = suggestMeetingSlots(
        MeetingKind.coffee,
        now: now,
        busyA: [TimeSpan(wed(7), wed(7, 30))],
        busyB: [TimeSpan(wed(5), wed(6))],
      );
      expect(days.first.starts.map(hm), ['6:00', '7:30', '8:00']);
    });

    test('a day with nothing free is dropped', () {
      final days = suggestMeetingSlots(
        MeetingKind.lunch,
        now: now,
        busyA: [TimeSpan(wed(10), wed(14))],
        busyB: const [],
      );
      expect(dayLabels(days), ['10/15', '10/16', '10/19', '10/20']);
    });

    test('a lunch filter never lets a coffee time through', () {
      final days = suggestMeetingSlots(MeetingKind.lunch, now: now, busyA: const [], busyB: const []);
      expect([for (final d in days) ...d.starts].every((t) => t.hour >= 11 && t.hour <= 12), isTrue);
    });
  });

  group('helpers', () {
    test('the calendar search window spans the first to the end of the last time', () {
      final days = candidateMeetingDays(MeetingKind.coffee, now: DateTime(2026, 10, 12, 5));
      final window = meetingSearchWindow(days, durationMinutes: 60)!;
      expect(window.start, DateTime(2026, 10, 14, 6));
      expect(window.end, DateTime(2026, 10, 20, 9));
      expect(meetingSearchWindow(const [], durationMinutes: 60), isNull);
    });

    test('the pickers start on the first candidate, or the next whole hour for Organic Life', () {
      final now = DateTime(2026, 10, 12, 9, 20);
      expect(defaultMeetingStart(MeetingKind.coffee, now: now), DateTime(2026, 10, 15, 6));
      expect(defaultMeetingStart(MeetingKind.lunch, now: now), DateTime(2026, 10, 14, 11));
      expect(defaultMeetingStart(MeetingKind.organicLife, now: now), DateTime(2026, 10, 14, 10));
      expect(
        defaultMeetingStart(MeetingKind.organicLife, now: DateTime(2026, 10, 12, 9)),
        DateTime(2026, 10, 14, 9),
      );
    });

    test('chip labels are short', () {
      expect(formatChipTime(DateTime(2026, 10, 14, 6)), '6:00');
      expect(formatChipTime(DateTime(2026, 10, 14, 12, 30)), '12:30');
    });
  });

  group('PlacesService requests', () {
    const center = GeoPoint(39.05, -94.55);

    test('Text Search geocodes one address with only the location field', () {
      expect(PlacesService.textSearchBody('  1 Main St, Kansas City  '), {'textQuery': '1 Main St, Kansas City'});
      expect(PlacesService.headers('k', PlacesService.textSearchFieldMask), {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': 'k',
        'X-Goog-FieldMask': 'places.location',
      });
    });

    test('Nearby Search for coffee asks for coffee shops, nearest first', () {
      expect(PlacesService.nearbyBody(PlaceCategory.coffeeShop, center), {
        'includedTypes': ['coffee_shop'],
        'maxResultCount': 5,
        'rankPreference': 'DISTANCE',
        'locationRestriction': {
          'circle': {
            'center': {'latitude': 39.05, 'longitude': -94.55},
            'radius': 2500.0,
          },
        },
      });
      expect(PlacesService.nearbyFieldMask, 'places.displayName,places.formattedAddress,places.location');
    });

    test('Nearby Search for lunch asks for sit-down restaurants, no fast food', () {
      final body = PlacesService.nearbyBody(PlaceCategory.sitDownRestaurant, center, radiusMeters: 8000);
      expect(body['includedTypes'], ['restaurant']);
      expect(body['excludedTypes'], ['fast_food_restaurant']);
      expect(body['excludedPrimaryTypes'], containsAll(['cafe', 'coffee_shop', 'bar']));
      expect(body.containsKey('includedPrimaryTypes'), isFalse);
      expect((body['locationRestriction'] as Map)['circle']['radius'], 8000.0);
      // The body must be JSON-encodable as is.
      expect(() => jsonEncode(body), returnsNormally);
    });
  });

  group('PlacesService responses', () {
    test('Text Search: the first match, or null', () {
      final fixture = jsonDecode('''
        {"places": [
          {"location": {"latitude": 39.0997265, "longitude": -94.5785667}},
          {"location": {"latitude": 1, "longitude": 2}}
        ]}''');
      expect(PlacesService.parseTextSearch(fixture), const GeoPoint(39.0997265, -94.5785667));
      expect(PlacesService.parseTextSearch(jsonDecode('{}')), isNull);
      expect(PlacesService.parseTextSearch(jsonDecode('{"places": [{"location": {"latitude": "x"}}]}')), isNull);
      expect(PlacesService.parseTextSearch(null), isNull);
    });

    test('Nearby Search: names and addresses in order, nameless entries skipped', () {
      final fixture = jsonDecode('''
        {"places": [
          {"displayName": {"text": "Messenger Coffee", "languageCode": "en"},
           "formattedAddress": "1624 Grand Blvd, Kansas City, MO 64108, USA",
           "location": {"latitude": 39.0921, "longitude": -94.5806}},
          {"formattedAddress": "nameless"},
          {"displayName": {"text": "Thou Mayest"}}
        ]}''');
      final places = PlacesService.parseNearby(fixture);
      expect(places, hasLength(2));
      expect(places.first.label, 'Messenger Coffee, 1624 Grand Blvd, Kansas City, MO 64108, USA');
      expect(places.first.location, const GeoPoint(39.0921, -94.5806));
      expect(places.last.label, 'Thou Mayest');
      expect(PlacesService.parseNearby(jsonDecode('{}')), isEmpty);
    });

    test('nearby widens to 8 km once when nothing is within 2.5 km', () async {
      final radii = <Object?>[];
      final service = PlacesService(
        apiKey: 'test-key',
        client: MockClient((request) async {
          expect(request.url, PlacesService.nearbySearchUrl);
          expect(request.headers['X-Goog-Api-Key'], 'test-key');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          radii.add(body['locationRestriction']['circle']['radius']);
          return radii.length == 1
              ? http.Response('{}', 200)
              : http.Response('{"places": [{"displayName": {"text": "Far Cafe"}, "formattedAddress": "9 Rd"}]}', 200);
        }),
      );
      final places = await service.nearby(PlaceCategory.coffeeShop, const GeoPoint(39, -94));
      expect(radii, [2500, 8000]);
      expect(places.single.label, 'Far Cafe, 9 Rd');
    });

    test('geocode: a failed call throws, no match is null, no key does nothing', () async {
      final failing = PlacesService(
        apiKey: 'k',
        client: MockClient((_) async => http.Response('nope', 500)),
      );
      expect(failing.geocode('1 Main St'), throwsA(isA<PlacesException>()));

      final empty = PlacesService(
        apiKey: 'k',
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(await empty.geocode('Nowhere at all'), isNull);

      var called = false;
      final keyless = PlacesService(
        apiKey: '',
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      expect(await keyless.geocode('1 Main St'), isNull);
      expect(await keyless.nearby(PlaceCategory.coffeeShop, const GeoPoint(0, 0)), isEmpty);
      expect(called, isFalse);
    });
  });

  group('MeetingSpotService.parseMidpoint', () {
    test('reads a point or who is missing', () {
      expect(MeetingSpotService.parseMidpoint({'lat': 39.05, 'lng': -94.55})?.point,
          const GeoPoint(39.05, -94.55));
      expect(MeetingSpotService.parseMidpoint({'lat': 39, 'lng': -94})?.point, const GeoPoint(39, -94));
      expect(MeetingSpotService.parseMidpoint({'missing': 'me'})?.missing, 'me');
      expect(MeetingSpotService.parseMidpoint('{"missing": "other"}')?.missing, 'other');
      expect(MeetingSpotService.parseMidpoint({'lat': 'x'}), isNull);
      expect(MeetingSpotService.parseMidpoint({'lat': 120, 'lng': 0}), isNull);
      expect(MeetingSpotService.parseMidpoint(null), isNull);
    });
  });
}
