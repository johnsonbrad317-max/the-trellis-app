import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A point on the map, in degrees.
@immutable
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) => other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'GeoPoint($lat, $lng)';
}

/// What kind of place to look for near the midpoint.
enum PlaceCategory { coffeeShop, sitDownRestaurant }

/// One place Google suggested.
@immutable
class PlaceSuggestion {
  const PlaceSuggestion({required this.name, required this.address, this.location});

  final String name;
  final String address;
  final GeoPoint? location;

  /// What goes in the meeting's Location field: "Name, formatted address".
  String get label => address.isEmpty ? name : '$name, $address';

  @override
  String toString() => 'PlaceSuggestion($label)';
}

/// A Places API call failed in transit (offline, a non-200 answer, a garbled
/// body) — as opposed to succeeding with no match.
class PlacesException implements Exception {
  const PlacesException(this.reason);

  final String reason;

  @override
  String toString() => 'PlacesException($reason)';
}

/// The two Google Places API (New) calls the midway suggestion needs, with
/// the request bodies and response parsing kept pure (static) so they can be
/// unit-tested without a network (test/meeting_activity_test.dart).
///
///   * Text Search — turns one of MY addresses into a point. Only ever called
///     with the signed-in person's own home / work address.
///   * Nearby Search — coffee shops or sit-down restaurants around the
///     (rounded) midpoint the server worked out.
///
/// Uses the same `--dart-define=GOOGLE_PLACES_API_KEY` as the location
/// autocomplete field (Places API (New) must be enabled on that key). With no
/// key every call is a quiet no-op.
class PlacesService {
  PlacesService({this.client, String? apiKey}) : apiKey = apiKey ?? configuredApiKey;

  static final PlacesService instance = PlacesService();

  static const String configuredApiKey = String.fromEnvironment('GOOGLE_PLACES_API_KEY');

  static final Uri textSearchUrl = Uri.parse('https://places.googleapis.com/v1/places:searchText');
  static final Uri nearbySearchUrl =
      Uri.parse('https://places.googleapis.com/v1/places:searchNearby');

  static const String textSearchFieldMask = 'places.location';
  static const String nearbyFieldMask =
      'places.displayName,places.formattedAddress,places.location';

  /// First search radius around the midpoint, then the wider retry.
  static const double nearRadiusMeters = 2500;
  static const double wideRadiusMeters = 8000;

  static const Duration _timeout = Duration(seconds: 12);

  /// Swappable for tests; null uses the default http client.
  final http.Client? client;
  final String apiKey;

  bool get isConfigured => apiKey.isNotEmpty;

  /// Headers for a Places (New) POST.
  static Map<String, String> headers(String apiKey, String fieldMask) => {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': fieldMask,
      };

  /// Text Search body for geocoding one address.
  static Map<String, Object?> textSearchBody(String address) => {'textQuery': address.trim()};

  /// The first result's location from a Text Search answer, or null if there
  /// was no usable match.
  static GeoPoint? parseTextSearch(Object? json) {
    final places = _places(json);
    if (places.isEmpty) return null;
    return _point(places.first['location']);
  }

  /// Nearby Search body: coffee shops, or sit-down restaurants, nearest first,
  /// at most five. A sit-down place is anything typed a restaurant (an
  /// "italian_restaurant" carries "restaurant" too — asking for it as the
  /// PRIMARY type would miss most of them), minus fast food and anything
  /// whose main business is coffee, pastries, drinks or takeaway.
  static Map<String, Object?> nearbyBody(
    PlaceCategory category,
    GeoPoint center, {
    double radiusMeters = nearRadiusMeters,
  }) =>
      {
        ...switch (category) {
          PlaceCategory.coffeeShop => {
              'includedTypes': ['coffee_shop'],
            },
          PlaceCategory.sitDownRestaurant => {
              'includedTypes': ['restaurant'],
              'excludedTypes': ['fast_food_restaurant'],
              'excludedPrimaryTypes': ['cafe', 'coffee_shop', 'bakery', 'bar', 'meal_takeaway'],
            },
        },
        'maxResultCount': 5,
        'rankPreference': 'DISTANCE',
        'locationRestriction': {
          'circle': {
            'center': {'latitude': center.lat, 'longitude': center.lng},
            'radius': radiusMeters,
          },
        },
      };

  /// The places in a Nearby Search answer, in Google's order; entries with
  /// no name are skipped.
  static List<PlaceSuggestion> parseNearby(Object? json) => [
        for (final place in _places(json))
          if (_displayName(place['displayName']) case final name? when name.isNotEmpty)
            PlaceSuggestion(
              name: name,
              address: (place['formattedAddress'] as String?)?.trim() ?? '',
              location: _point(place['location']),
            ),
      ];

  /// Geocodes [address]. Null when Google has no match (or there is no key);
  /// throws [PlacesException] when the call itself failed, so a caller can
  /// tell "no such place" from "try again later".
  Future<GeoPoint?> geocode(String address) async {
    if (!isConfigured || address.trim().isEmpty) return null;
    final json = await _post(textSearchUrl, textSearchFieldMask, textSearchBody(address));
    return parseTextSearch(json);
  }

  /// Up to five places of [category] near [center]: within 2.5 km, or within
  /// 8 km if nothing is that close. Empty on any failure or with no key.
  Future<List<PlaceSuggestion>> nearby(PlaceCategory category, GeoPoint center) async {
    if (!isConfigured) return const [];
    try {
      for (final radius in const [nearRadiusMeters, wideRadiusMeters]) {
        final json = await _post(
          nearbySearchUrl,
          nearbyFieldMask,
          nearbyBody(category, center, radiusMeters: radius),
        );
        final places = parseNearby(json);
        if (places.isNotEmpty) return places;
      }
    } catch (error) {
      debugPrint('PlacesService.nearby failed: $error');
    }
    return const [];
  }

  Future<Object?> _post(Uri url, String fieldMask, Map<String, Object?> body) async {
    final client = this.client;
    final Future<http.Response> request = client == null
        ? http.post(url, headers: headers(apiKey, fieldMask), body: jsonEncode(body))
        : client.post(url, headers: headers(apiKey, fieldMask), body: jsonEncode(body));
    final http.Response response;
    try {
      response = await request.timeout(_timeout);
    } catch (error) {
      throw PlacesException('network: ${error.runtimeType}');
    }
    if (response.statusCode != 200) throw PlacesException('HTTP ${response.statusCode}');
    try {
      return jsonDecode(response.body);
    } catch (_) {
      throw const PlacesException('unreadable body');
    }
  }

  static List<Map<String, dynamic>> _places(Object? json) {
    if (json is! Map) return const [];
    final places = json['places'];
    if (places is! List) return const [];
    return [
      for (final place in places)
        if (place is Map) Map<String, dynamic>.from(place),
    ];
  }

  static String? _displayName(Object? value) {
    if (value is Map) return (value['text'] as String?)?.trim();
    if (value is String) return value.trim();
    return null;
  }

  static GeoPoint? _point(Object? value) {
    if (value is! Map) return null;
    final lat = value['latitude'];
    final lng = value['longitude'];
    if (lat is! num || lng is! num) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return GeoPoint(lat.toDouble(), lng.toDouble());
  }
}
