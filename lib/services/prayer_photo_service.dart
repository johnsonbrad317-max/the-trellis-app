import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../models/prayer_item.dart';
import 'supabase_client.dart';

/// Asks the server for a temporary link to the photo at [path], good for
/// [expiresInSeconds].
typedef PrayerPhotoSigner = Future<String> Function(String path, int expiresInSeconds);

/// Stores [bytes] at [path], replacing whatever is already there.
typedef PrayerPhotoUploader = Future<void> Function(String path, Uint8List bytes);

/// Deletes the photo at [path].
typedef PrayerPhotoRemover = Future<void> Function(String path);

/// Lets the user choose a photo; resolves to null if they back out.
typedef PrayerPhotoPicker = Future<Uint8List?> Function();

/// How choosing a photo ended.
enum PrayerPhotoPickStatus {
  /// A usable photo was chosen — its bytes are in [PrayerPhotoPick.bytes].
  picked,

  /// The user closed the picker without choosing anything.
  cancelled,

  /// The photo is over [PrayerPhotoService.maxBytes].
  tooLarge,

  /// Not a kind of image every device can show (JPEG, PNG, WebP or GIF).
  unsupported,

  /// The device's photo picker could not be opened at all.
  unavailable,
}

/// The outcome of [PrayerPhotoService.pick].
class PrayerPhotoPick {
  const PrayerPhotoPick(this.status, [this.bytes]);

  final PrayerPhotoPickStatus status;

  /// The chosen photo, only when [status] is [PrayerPhotoPickStatus.picked].
  final Uint8List? bytes;

  /// What to tell the user when no photo came back — null when one did, or
  /// when they simply cancelled (which needs no explanation).
  String? get notice => switch (status) {
        PrayerPhotoPickStatus.picked || PrayerPhotoPickStatus.cancelled => null,
        PrayerPhotoPickStatus.tooLarge => 'That photo is too large. Choose one under 5 MB.',
        PrayerPhotoPickStatus.unsupported =>
          "That kind of photo can't be used here. Try a different one.",
        PrayerPhotoPickStatus.unavailable =>
          "Couldn't open your photos. Check photo access in Settings.",
      };
}

class _SignedUrl {
  const _SignedUrl(this.url, this.refreshAfter);

  final String url;
  final DateTime refreshAfter;
}

/// Everything to do with the photo on a prayer card: choosing one from the
/// device, storing it in the private `prayer-photos` bucket, and handing out
/// temporary links for showing it.
///
/// The bucket is private, so a photo can only be displayed through a signed
/// link that expires. Those links are remembered here until shortly before
/// they run out — a garden of thirty prayers asks the server for thirty links
/// once, not on every rebuild. Listeners are told whenever a photo changes so
/// a medallion already on screen can pick up the new one.
///
/// Every server call can be swapped out through the constructor, which is how
/// the tests exercise the cache without a network.
class PrayerPhotoService extends ChangeNotifier {
  PrayerPhotoService({
    PrayerPhotoSigner? signer,
    PrayerPhotoUploader? uploader,
    PrayerPhotoRemover? remover,
    PrayerPhotoPicker? picker,
    String? Function()? currentUserId,
    DateTime Function()? clock,
  })  : _injectedSigner = signer,
        _uploader = uploader ?? _uploadToSupabase,
        _remover = remover ?? _removeFromSupabase,
        _picker = picker ?? _pickFromGallery,
        _currentUserId = currentUserId ?? _supabaseUserId,
        _clock = clock ?? DateTime.now;

  /// The one instance the app shares, so every screen draws on the same cache.
  static final PrayerPhotoService instance = PrayerPhotoService();

  /// Largest photo accepted. Picked photos are already scaled to 1000px wide,
  /// so anything near this is a file the picker could not shrink.
  static const maxBytes = 5 * 1024 * 1024;

  /// How long a signed link is valid for.
  static const linkLifetime = Duration(hours: 1);

  /// A link this close to expiring is replaced rather than handed out — an
  /// image that starts loading must not have its link die mid-download.
  static const refreshMargin = Duration(minutes: 5);

  /// After a link could not be made (offline, or the bucket is not set up
  /// yet), how long before asking again — so a failing garden does not send a
  /// request per prayer on every rebuild.
  static const retryAfterFailure = Duration(minutes: 1);

  /// How many just-chosen photos are kept in memory for instant display.
  static const _rememberedPhotos = 6;

  final PrayerPhotoSigner? _injectedSigner;
  final PrayerPhotoUploader _uploader;
  final PrayerPhotoRemover _remover;
  final PrayerPhotoPicker _picker;
  final String? Function() _currentUserId;
  final DateTime Function() _clock;

  final Map<String, _SignedUrl> _urls = {};
  final Map<String, Future<String?>> _inFlight = {};
  final Map<String, DateTime> _failedAt = {};

  /// Bumped whenever a path is invalidated, so a link request that was already
  /// on its way is not stored once it lands.
  final Map<String, int> _generation = {};

  /// A marker added to links for a path whose photo has been replaced, so the
  /// new link can never be mistaken (by a cache) for the old photo's.
  final Map<String, String> _nonces = {};

  /// Photos chosen this session, by path — shown straight from memory instead
  /// of being downloaded again a moment after they were uploaded.
  final Map<String, Uint8List> _recentBytes = {};

  // ---------------------------------------------------------------------
  // Choosing
  // ---------------------------------------------------------------------

  /// Opens the device's photo library (never the camera) and returns the
  /// chosen photo, already checked for size and kind. Never throws.
  Future<PrayerPhotoPick> pick() async {
    final Uint8List? bytes;
    try {
      bytes = await _picker();
    } catch (error) {
      debugPrint('Prayer photo picker failed: ${error.runtimeType}');
      return const PrayerPhotoPick(PrayerPhotoPickStatus.unavailable);
    }
    if (bytes == null) return const PrayerPhotoPick(PrayerPhotoPickStatus.cancelled);
    return check(bytes);
  }

  /// Decides whether [bytes] can be used as a prayer photo.
  static PrayerPhotoPick check(Uint8List bytes) {
    if (bytes.length > maxBytes) return const PrayerPhotoPick(PrayerPhotoPickStatus.tooLarge);
    if (!_isDisplayableImage(bytes)) {
      return const PrayerPhotoPick(PrayerPhotoPickStatus.unsupported);
    }
    return PrayerPhotoPick(PrayerPhotoPickStatus.picked, bytes);
  }

  /// True for the formats every platform the app runs on can decode. The
  /// picker hands back JPEG for nearly everything (it re-encodes when it
  /// scales), but a PNG can come through unchanged, and a format a phone
  /// cannot draw (e.g. HEIC on Android) must be turned away here rather than
  /// saved as a photo that never appears.
  static bool _isDisplayableImage(Uint8List b) {
    bool startsWith(List<int> magic, [int offset = 0]) {
      if (b.length < offset + magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (b[offset + i] != magic[i]) return false;
      }
      return true;
    }

    final jpeg = startsWith(const [0xFF, 0xD8, 0xFF]);
    final png = startsWith(const [0x89, 0x50, 0x4E, 0x47]);
    final gif = startsWith(const [0x47, 0x49, 0x46, 0x38]);
    final webp = startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
        startsWith(const [0x57, 0x45, 0x42, 0x50], 8);
    return jpeg || png || gif || webp;
  }

  // ---------------------------------------------------------------------
  // Storing
  // ---------------------------------------------------------------------

  /// Stores [bytes] as the photo for the prayer [prayerId], replacing any
  /// earlier one, and returns the path to save on the prayer. Throws if the
  /// upload fails (or nobody is signed in) — the caller decides what to say.
  Future<String> upload({required String prayerId, required Uint8List bytes}) async {
    final userId = _currentUserId();
    if (userId == null) throw StateError('No signed-in user to store a prayer photo for.');
    final path = prayerPhotoPathFor(userId: userId, prayerId: prayerId);
    await _uploader(path, bytes);
    // Any link handed out so far points at the old photo.
    _forget(path);
    _recentBytes.remove(path);
    _recentBytes[path] = bytes;
    while (_recentBytes.length > _rememberedPhotos) {
      _recentBytes.remove(_recentBytes.keys.first);
    }
    notifyListeners();
    return path;
  }

  /// Deletes the stored photo at [path]. Best-effort: resolves to whether the
  /// server confirmed it, and never throws — a photo left behind is private
  /// and harmless, so a failed clean-up is not worth interrupting anyone for.
  Future<bool> remove(String path) async {
    var removed = true;
    try {
      await _remover(path);
    } catch (error) {
      debugPrint('Prayer photo clean-up failed: ${error.runtimeType}');
      removed = false;
    }
    invalidate(path);
    return removed;
  }

  // ---------------------------------------------------------------------
  // Showing
  // ---------------------------------------------------------------------

  /// A link for displaying the photo at [path], or null if one cannot be made
  /// right now (offline, the photo is gone, the bucket does not exist yet).
  /// Never throws. Repeated calls share one cached link until it nears expiry.
  Future<String?> urlFor(String path) {
    final cached = cachedUrlFor(path);
    if (cached != null) return Future<String?>.value(cached);

    final failedAt = _failedAt[path];
    if (failedAt != null && _clock().difference(failedAt) < retryAfterFailure) {
      return Future<String?>.value();
    }
    return _inFlight[path] ??= _sign(path);
  }

  /// The link already in hand for [path], if it is still fresh — lets a
  /// widget draw the photo on its very first frame instead of flashing
  /// initials while it awaits [urlFor].
  String? cachedUrlFor(String path) {
    final cached = _urls[path];
    if (cached == null) return null;
    if (!_clock().isBefore(cached.refreshAfter)) {
      _urls.remove(path);
      return null;
    }
    return cached.url;
  }

  /// The photo chosen for [path] earlier this session, if it is still held in
  /// memory.
  Uint8List? bytesFor(String path) => _recentBytes[path];

  /// Forgets everything known about [path] — call after its photo has been
  /// replaced or removed, so nothing goes on showing the old one.
  void invalidate(String path) {
    _forget(path);
    _recentBytes.remove(path);
    notifyListeners();
  }

  /// Forgets every link and remembered photo (e.g. when the account changes).
  void clear() {
    for (final path in {..._urls.keys, ..._inFlight.keys}) {
      _generation[path] = (_generation[path] ?? 0) + 1;
    }
    _urls.clear();
    _inFlight.clear();
    _failedAt.clear();
    _recentBytes.clear();
    notifyListeners();
  }

  void _forget(String path) {
    _urls.remove(path);
    _inFlight.remove(path);
    _failedAt.remove(path);
    _generation[path] = (_generation[path] ?? 0) + 1;
    _nonces[path] = _clock().microsecondsSinceEpoch.toString();
  }

  Future<String?> _sign(String path) async {
    final generation = _generation[path] ?? 0;
    bool stillCurrent() => (_generation[path] ?? 0) == generation;

    String? url;
    try {
      final signer = _injectedSigner ?? _signWithSupabase;
      url = await signer(path, linkLifetime.inSeconds);
      if (stillCurrent()) {
        _urls[path] = _SignedUrl(url, _clock().add(linkLifetime - refreshMargin));
        _failedAt.remove(path);
      }
    } catch (error) {
      // The error's class only: its text can carry the path, which names the
      // user and the prayer.
      debugPrint('Prayer photo link failed: ${error.runtimeType}');
      if (stillCurrent()) _failedAt[path] = _clock();
    }
    if (stillCurrent()) _inFlight.remove(path);
    return url;
  }

  // ---------------------------------------------------------------------
  // The real thing (Supabase Storage + the device's photo picker)
  // ---------------------------------------------------------------------

  Future<String> _signWithSupabase(String path, int expiresInSeconds) => supabase.storage
      .from(prayerPhotoBucket)
      .createSignedUrl(path, expiresInSeconds, cacheNonce: _nonces[path]);

  static Future<void> _uploadToSupabase(String path, Uint8List bytes) async {
    await supabase.storage.from(prayerPhotoBucket).uploadBinary(
          path,
          bytes,
          // upsert: choosing a new photo overwrites the old one in place.
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
  }

  static Future<void> _removeFromSupabase(String path) async {
    await supabase.storage.from(prayerPhotoBucket).remove([path]);
  }

  static String? _supabaseUserId() => supabase.auth.currentUser?.id;

  /// Library only — the app never opens the camera. The photo is scaled down
  /// and re-compressed on the device before it is read, and read as bytes
  /// (not through a file path) so the same code works in a browser.
  static Future<Uint8List?> _pickFromGallery() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1000,
      imageQuality: 80,
      // The system picker hands over just the one chosen photo; asking for
      // full metadata would instead prompt for access to the whole library.
      requestFullMetadata: false,
    );
    return file?.readAsBytes();
  }
}
