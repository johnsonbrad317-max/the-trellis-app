import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/prayer_photo_service.dart';
import '../theme/app_colors.dart';
import 'brass_glyph.dart';

/// The round portrait on a prayer: the person's photo inside a brass ring, or
/// — when there is no photo, while it loads, or if it fails to load — their
/// initials on forest green. Given a [glyph] instead (a situation rather than
/// a person), it draws that engraved mark on parchment.
///
/// A photo comes either from [photoBytes] (one just chosen and not yet
/// uploaded) or from [photoPath] (one stored in the private bucket, shown
/// through a temporary link from [PrayerPhotoService]). Photos are private to
/// the Runner who owns the prayer, so this is never given a path on a
/// Witness's screen.
class PrayerMedallion extends StatefulWidget {
  const PrayerMedallion({
    super.key,
    required this.name,
    this.photoPath,
    this.photoBytes,
    this.glyph,
    this.size = 40,
    this.service,
  });

  /// Whose prayer this is — the source of the initials.
  final String name;

  /// Where the stored photo lives, or null for none.
  final String? photoPath;

  /// A photo held in memory; takes precedence over [photoPath].
  final Uint8List? photoBytes;

  /// Drawn in place of initials when the prayer is not for a person.
  final BrassGlyphKind? glyph;

  /// The medallion's full diameter, ring included.
  final double size;

  /// Where links to stored photos come from; the app's shared instance unless
  /// a test supplies its own.
  final PrayerPhotoService? service;

  /// One or two initials for [name]. Splits on `characters`, not code units:
  /// a name that opens with an emoji or an accented letter must not be cut
  /// mid-character.
  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first.characters.first;
    if (parts.length == 1) return first.toUpperCase();
    return (first + parts.last.characters.first).toUpperCase();
  }

  @override
  State<PrayerMedallion> createState() => _PrayerMedallionState();
}

class _PrayerMedallionState extends State<PrayerMedallion> {
  late PrayerPhotoService _service = widget.service ?? PrayerPhotoService.instance;

  /// The temporary link for [PrayerMedallion.photoPath], once known.
  String? _url;

  /// Counts lookups, so a slow answer for a path this medallion has since
  /// moved on from is ignored.
  int _lookup = 0;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onPhotosChanged);
    final path = widget.photoPath;
    if (path != null) {
      // A link already in hand is used on the very first frame.
      _url = _service.cachedUrlFor(path);
      if (_url == null) _lookUp(path);
    }
  }

  @override
  void didUpdateWidget(PrayerMedallion oldWidget) {
    super.didUpdateWidget(oldWidget);
    final service = widget.service ?? PrayerPhotoService.instance;
    if (!identical(service, _service)) {
      _service.removeListener(_onPhotosChanged);
      _service = service..addListener(_onPhotosChanged);
    }
    if (widget.photoPath != oldWidget.photoPath) _refresh();
  }

  @override
  void dispose() {
    _service.removeListener(_onPhotosChanged);
    super.dispose();
  }

  /// A photo somewhere was replaced or removed. The path stays the same when
  /// a photo is swapped for another, so this is the only way to hear of it.
  void _onPhotosChanged() {
    if (mounted) setState(_refresh);
  }

  void _refresh() {
    _lookup++;
    final path = widget.photoPath;
    _url = path == null ? null : _service.cachedUrlFor(path);
    if (path != null && _url == null) _lookUp(path);
  }

  Future<void> _lookUp(String path) async {
    final lookup = ++_lookup;
    final url = await _service.urlFor(path);
    if (!mounted || lookup != _lookup || url == _url) return;
    setState(() => _url = url);
  }

  /// The photo fades in over the initials rather than popping.
  static Widget _fadeIn(BuildContext context, Widget child, int? frame, bool wasSynchronous) {
    if (wasSynchronous) return child;
    return AnimatedOpacity(
      opacity: frame == null ? 0 : 1,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      child: child,
    );
  }

  /// A photo that will not load simply leaves the initials showing.
  static Widget _nothing(BuildContext context, Object error, StackTrace? stackTrace) =>
      const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final large = size >= 72;
    final ring = large ? 2.0 : 1.4;
    final gap = large ? 4.0 : 2.0;
    final inner = size - 2 * (ring + gap);

    final path = widget.photoPath;
    final bytes = widget.photoBytes ?? (path == null ? null : _service.bytesFor(path));
    // Decode no larger than it is drawn: the stored photo is up to 1000px
    // wide, far more than a medallion needs.
    final decodeWidth = (inner * MediaQuery.devicePixelRatioOf(context) * 2).ceil();

    Widget? photo;
    if (bytes != null) {
      photo = Image.memory(
        bytes,
        key: ObjectKey(bytes),
        fit: BoxFit.cover,
        cacheWidth: decodeWidth,
        gaplessPlayback: true,
        frameBuilder: _fadeIn,
        errorBuilder: _nothing,
      );
    } else if (_url != null) {
      photo = Image.network(
        _url!,
        key: ValueKey(_url),
        fit: BoxFit.cover,
        cacheWidth: decodeWidth,
        gaplessPlayback: true,
        frameBuilder: _fadeIn,
        errorBuilder: _nothing,
      );
    }

    final glyph = widget.glyph;
    final Widget plain = glyph != null
        ? ColoredBox(
            color: AppColors.parchmentLight,
            child: Center(
              child: BrassGlyph(glyph, size: inner * 0.5, color: AppColors.forestGreen),
            ),
          )
        : ColoredBox(
            color: AppColors.forestGreen,
            child: Padding(
              padding: EdgeInsets.all(inner * 0.16),
              // Scaled to fit and deliberately not grown by the system text
              // size: the letters are a mark inside a fixed circle, and the
              // name itself is always written out beside it.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  PrayerMedallion.initialsOf(widget.name),
                  textScaler: TextScaler.noScaling,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: inner * 0.42,
                        height: 1,
                        color: AppColors.parchmentLight,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                ),
              ),
            ),
          );

    // Decorative: wherever a medallion appears, the name is beside it in text.
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(gap),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.parchmentLight,
          border: Border.all(color: AppColors.antiqueBrass, width: ring),
        ),
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: [plain, ?photo],
          ),
        ),
      ),
    );
  }
}
