import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/calendar_connection.dart';
import 'package:trellis/services/calendar_service.dart';

void main() {
  _rateLimitTests();

  group('CalendarProvider', () {
    test('maps to and from its database value', () {
      expect(CalendarProvider.google.dbValue, 'google');
      expect(CalendarProvider.outlook.dbValue, 'outlook');
      expect(CalendarProvider.apple.dbValue, 'apple');
      for (final provider in CalendarProvider.values) {
        expect(CalendarProvider.fromDb(provider.dbValue), provider);
      }
      expect(CalendarProvider.fromDb('yahoo'), isNull);
      expect(CalendarProvider.fromDb(null), isNull);
    });

    test('has the display labels', () {
      expect(CalendarProvider.google.label, 'Google Calendar');
      expect(CalendarProvider.outlook.label, 'Outlook Calendar');
      expect(CalendarProvider.apple.label, 'Apple Calendar');
    });
  });

  group('CalendarConnection.fromJson', () {
    test('parses an active connection', () {
      final connection = CalendarConnection.fromJson({
        'provider': 'google',
        'status': 'active',
        'connected_at': '2026-10-01T12:00:00+00:00',
      });
      expect(connection.provider, CalendarProvider.google);
      expect(connection.status, CalendarConnectionStatus.active);
      expect(connection.isActive, isTrue);
      expect(connection.connectedAt!.toUtc(), DateTime.utc(2026, 10, 1, 12));
    });

    test('parses needs_reauth', () {
      final connection = CalendarConnection.fromJson({
        'provider': 'apple',
        'status': 'needs_reauth',
        'connected_at': null,
      });
      expect(connection.status, CalendarConnectionStatus.needsReauth);
      expect(connection.isActive, isFalse);
      expect(connection.connectedAt, isNull);
    });

    test('rejects an unknown provider', () {
      expect(
        () => CalendarConnection.fromJson({'provider': 'yahoo', 'status': 'active'}),
        throwsFormatException,
      );
    });
  });

  group('SharedSlot.fromJson', () {
    test('parses ISO start/end into local times', () {
      final slot = SharedSlot.fromJson({
        'start': '2026-10-06T17:00:00.000Z',
        'end': '2026-10-06T19:00:00.000Z',
      });
      expect(slot.start.toUtc(), DateTime.utc(2026, 10, 6, 17));
      expect(slot.end.toUtc(), DateTime.utc(2026, 10, 6, 19));
      expect(slot.start.isUtc, isFalse);
    });

    test('rejects a missing or malformed time', () {
      expect(() => SharedSlot.fromJson({'start': 'nope', 'end': 'nope'}), throwsFormatException);
      expect(() => SharedSlot.fromJson({'start': '2026-10-06T17:00:00Z'}), throwsFormatException);
    });
  });

  group('PairAvailability.fromJson', () {
    test('parses a full response', () {
      final availability = PairAvailability.fromJson({
        'suggestions': [
          {'start': '2026-10-06T17:00:00.000Z', 'end': '2026-10-06T19:00:00.000Z'},
          {'start': '2026-10-07T17:00:00.000Z', 'end': '2026-10-07T19:00:00.000Z'},
        ],
        'both_connected': true,
        'me_connected': true,
        'other_connected': true,
      });
      expect(availability.suggestions, hasLength(2));
      expect(availability.bothConnected, isTrue);
    });

    test('empty suggestions with one side missing', () {
      final availability = PairAvailability.fromJson({
        'suggestions': <dynamic>[],
        'both_connected': false,
        'me_connected': true,
        'other_connected': false,
      });
      expect(availability.suggestions, isEmpty);
      expect(availability.meConnected, isTrue);
      expect(availability.otherConnected, isFalse);
      expect(availability.bothConnected, isFalse);
    });

    test('skips malformed slots and tolerates missing fields', () {
      final availability = PairAvailability.fromJson({
        'suggestions': [
          {'start': 'bad', 'end': 'bad'},
          'not a map',
          {'start': '2026-10-06T17:00:00.000Z', 'end': '2026-10-06T19:00:00.000Z'},
        ],
      });
      expect(availability.suggestions, hasLength(1));
      expect(availability.meConnected, isFalse);
      expect(availability.otherConnected, isFalse);
    });
  });
}

// ---------------------------------------------------------------------------
// Rate limiting (calendar-availability answers 429 when asked too often)
// ---------------------------------------------------------------------------
void _rateLimitTests() {
  group('PairAvailability.rateLimited', () {
    test('is flagged, knows nothing about calendars and has no suggestions', () {
      const answer = PairAvailability.rateLimited(30);
      expect(answer.isRateLimited, isTrue);
      expect(answer.suggestions, isEmpty);
      expect(answer.meConnected, isFalse);
      expect(answer.otherConnected, isFalse);
      expect(answer.bothConnected, isFalse);
    });

    test('an ordinary answer is not rate limited', () {
      expect(PairAvailability.none.isRateLimited, isFalse);
      expect(PairAvailability.fromJson(const {'me_connected': true}).isRateLimited, isFalse);
    });

    test('says how long to wait in plain words', () {
      expect(const PairAvailability.rateLimited(1).retryAfterLabel, 'about a minute');
      expect(const PairAvailability.rateLimited(90).retryAfterLabel, 'about a minute');
      expect(const PairAvailability.rateLimited(91).retryAfterLabel, 'about 2 minutes');
      expect(const PairAvailability.rateLimited(600).retryAfterLabel, 'about 10 minutes');
      expect(const PairAvailability.rateLimited(3600).retryAfterLabel, 'about an hour');
    });
  });

  group('CalendarService.retryAfterSecondsFrom', () {
    test('reads the server\'s wait', () {
      expect(CalendarService.retryAfterSecondsFrom({'retry_after_seconds': 42}), 42);
      expect(CalendarService.retryAfterSecondsFrom({'retry_after_seconds': 41.2}), 42);
      expect(CalendarService.retryAfterSecondsFrom('{"retry_after_seconds": 7}'), 7);
    });

    test('falls back to a minute for anything unusable', () {
      for (final bad in <Object?>[
        null,
        'nope',
        const {},
        const {'retry_after_seconds': 'soon'},
        const {'retry_after_seconds': 0},
        const {'retry_after_seconds': -5},
        const {'retry_after_seconds': double.nan},
      ]) {
        expect(CalendarService.retryAfterSecondsFrom(bad), 60, reason: '$bad');
      }
    });

    test('never asks the person to wait more than an hour', () {
      expect(CalendarService.retryAfterSecondsFrom({'retry_after_seconds': 999999}), 3600);
    });
  });
}
