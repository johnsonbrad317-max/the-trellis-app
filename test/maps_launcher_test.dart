import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/services/maps_launcher.dart';

void main() {
  group('mapsUriFor', () {
    test('iOS and macOS use Apple Maps', () {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
        final uri = mapsUriFor('1 Main St', platform);
        expect(uri.scheme, 'https');
        expect(uri.host, 'maps.apple.com');
        expect(uri.queryParameters['q'], '1 Main St');
      }
    });

    test('Android uses a geo: intent', () {
      final uri = mapsUriFor('1 Main St', TargetPlatform.android);
      expect(uri.scheme, 'geo');
      expect(uri.toString(), 'geo:0,0?q=1+Main+St');
    });

    test('other platforms use Google Maps on the web', () {
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        final uri = mapsUriFor('1 Main St', platform);
        expect(uri.scheme, 'https');
        expect(uri.host, 'www.google.com');
        expect(uri.path, '/maps/search/');
        expect(uri.queryParameters['api'], '1');
        expect(uri.queryParameters['query'], '1 Main St');
      }
    });

    test('ampersands and other reserved characters are percent-encoded', () {
      final uri = mapsUriFor('Smith & Sons, 5th #2', TargetPlatform.iOS);
      expect(uri.toString(), contains('q=Smith+%26+Sons%2C+5th+%232'));
      // Round-trips: the ampersand never splits the query.
      expect(uri.queryParameters, {'q': 'Smith & Sons, 5th #2'});
    });

    test('unicode is UTF-8 percent-encoded', () {
      final uri = mapsUriFor('Café Müller', TargetPlatform.android);
      expect(uri.toString(), 'geo:0,0?q=Caf%C3%A9+M%C3%BCller');
      expect(googleMapsWebUri('Café').queryParameters['query'], 'Café');
    });

    test('surrounding whitespace is trimmed', () {
      expect(
        mapsUriFor('  1 Main St \n', TargetPlatform.iOS).queryParameters['q'],
        '1 Main St',
      );
    });
  });

  test('openAddressInMaps returns false for a blank address without launching', () async {
    expect(await openAddressInMaps('   '), isFalse);
  });
}
