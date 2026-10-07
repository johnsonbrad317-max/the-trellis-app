import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/meeting_activity.dart';
import 'places_service.dart';
import 'supabase_client.dart';

/// Why there is no midway suggestion, or the suggestions themselves.
enum MidwayStatus {
  /// Places found near the midpoint ([MidwaySuggestion.places]).
  found,

  /// The signed-in person has no home or work location on file.
  missingMe,

  /// Their Runner / Witness has none on file (or isn't actively paired).
  missingOther,

  /// A midpoint exists but Google found nothing suitable nearby.
  nothingNearby,

  /// No API key, server not ready, offline… — show nothing at all.
  unavailable,
}

@immutable
class MidwaySuggestion {
  const MidwaySuggestion(this.status, [this.places = const []]);

  final MidwayStatus status;
  final List<PlaceSuggestion> places;
}

/// The server's answer from `get_meeting_midpoint` (migration 027).
@immutable
class MidpointAnswer {
  const MidpointAnswer.point(GeoPoint this.point) : missing = null;
  const MidpointAnswer.missing(String this.missing) : point = null;

  /// The midpoint, already rounded to ~1 km by the server.
  final GeoPoint? point;

  /// 'me' or 'other'.
  final String? missing;
}

/// The midway meeting-spot suggestion, end to end.
///
/// Privacy: a person's home and work never leave their own phone except to
/// Google (to be geocoded — the phone's own addresses only) and to their own
/// row in The Trellis (`set_my_meeting_coordinates`). The partner's phone
/// only ever receives the midpoint the server computes, rounded to two
/// decimal places, and it is never shown — it is only the centre of a
/// Nearby Search.
class MeetingSpotService {
  MeetingSpotService._();

  static final MeetingSpotService instance = MeetingSpotService._();

  /// Swappable for tests.
  @visibleForTesting
  PlacesService places = PlacesService.instance;

  /// A fixed answer for [suggest] — for rendering the welcome deck's
  /// screenshots and for tests; null in the app.
  @visibleForTesting
  MidwaySuggestion? debugSuggestion;

  bool _checkedThisSession = false;

  /// Geocodes this person's own [home] and [work] and stores the points
  /// (`set_my_meeting_coordinates`; a null clears one). Never throws. If a
  /// lookup fails in transit nothing is written, so a good point already on
  /// file is not wiped by a flaky connection; an address Google cannot find
  /// is stored as "no point".
  Future<void> syncMyCoordinates({String? home, String? work}) async {
    if (!places.isConfigured) return;
    try {
      final homePoint = await _geocodeOrNull(home);
      final workPoint = await _geocodeOrNull(work);
      await supabase.rpc('set_my_meeting_coordinates', params: {
        'p_home_lat': homePoint?.lat,
        'p_home_lng': homePoint?.lng,
        'p_work_lat': workPoint?.lat,
        'p_work_lng': workPoint?.lng,
      });
    } catch (error) {
      debugPrint('MeetingSpotService.syncMyCoordinates skipped: $error');
    }
  }

  Future<GeoPoint?> _geocodeOrNull(String? address) async {
    final trimmed = address?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return places.geocode(trimmed);
  }

  /// Once per app session (from the first Connect tab build): if this person
  /// has an address on file with no point stored for it — addresses entered
  /// before this feature, or a save whose geocoding failed — geocode now.
  /// Quiet and fail-soft.
  Future<void> ensureMyCoordinates({String? home, String? work}) async {
    if (_checkedThisSession || !places.isConfigured) return;
    final hasHome = home?.trim().isNotEmpty ?? false;
    final hasWork = work?.trim().isNotEmpty ?? false;
    if (!hasHome && !hasWork) return;
    _checkedThisSession = true;
    try {
      final status = _asMap(await supabase.rpc('get_my_meeting_coordinates_status'));
      if (status == null) return;
      final needsHome = hasHome && status['home'] != true;
      final needsWork = hasWork && status['work'] != true;
      if (needsHome || needsWork) await syncMyCoordinates(home: home, work: work);
    } catch (error) {
      debugPrint('MeetingSpotService.ensureMyCoordinates skipped: $error');
    }
  }

  /// A coffee shop / sit-down restaurant midway between the signed-in person
  /// and [otherUserId], for [kind]. Organic Life gets nothing.
  Future<MidwaySuggestion> suggest(String otherUserId, MeetingKind kind) async {
    final fixed = debugSuggestion;
    if (fixed != null) return fixed;
    final category = switch (kind) {
      MeetingKind.coffee => PlaceCategory.coffeeShop,
      MeetingKind.lunch => PlaceCategory.sitDownRestaurant,
      MeetingKind.organicLife => null,
    };
    if (category == null || !places.isConfigured) {
      return const MidwaySuggestion(MidwayStatus.unavailable);
    }

    final MidpointAnswer? answer;
    try {
      answer = parseMidpoint(
        await supabase.rpc('get_meeting_midpoint', params: {'p_other_user_id': otherUserId}),
      );
    } catch (error) {
      debugPrint('MeetingSpotService.suggest: midpoint unavailable: $error');
      return const MidwaySuggestion(MidwayStatus.unavailable);
    }
    if (answer == null) return const MidwaySuggestion(MidwayStatus.unavailable);
    if (answer.missing == 'me') return const MidwaySuggestion(MidwayStatus.missingMe);
    final point = answer.point;
    if (point == null) return const MidwaySuggestion(MidwayStatus.missingOther);

    final found = await places.nearby(category, point);
    return found.isEmpty
        ? const MidwaySuggestion(MidwayStatus.nothingNearby)
        : MidwaySuggestion(MidwayStatus.found, found);
  }

  /// Reads `get_meeting_midpoint`'s `{lat, lng}` or `{missing: 'me'|'other'}`.
  /// Null for anything else.
  static MidpointAnswer? parseMidpoint(Object? raw) {
    final json = _asMap(raw);
    if (json == null) return null;
    final missing = json['missing'];
    if (missing == 'me' || missing == 'other') return MidpointAnswer.missing(missing as String);
    final lat = json['lat'];
    final lng = json['lng'];
    if (lat is num && lng is num && lat.abs() <= 90 && lng.abs() <= 180) {
      return MidpointAnswer.point(GeoPoint(lat.toDouble(), lng.toDouble()));
    }
    return null;
  }

  static Map<String, dynamic>? _asMap(Object? data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
