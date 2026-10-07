import 'package:flutter/material.dart';

import '../models/meeting_activity.dart';
import '../services/meeting_spot_service.dart';
import '../services/places_service.dart';
import 'bookplate_chip.dart';
import 'bookplate_plate.dart';

/// Sits under the Location field of a proposal sheet. For coffee or lunch it
/// asks for a coffee shop / sit-down restaurant midway between the signed-in
/// person and [otherUserId], puts the nearest one in [controller] (unless
/// something is already typed there) and offers up to two others as chips.
///
/// If either person has no home / work on file it says so in one line. With
/// no Places API key, the server not ready, or anything failing, it shows
/// nothing — the field is always free to type in. The midpoint itself is
/// never shown.
class MidwaySpotSuggestions extends StatefulWidget {
  const MidwaySpotSuggestions({
    super.key,
    required this.otherUserId,
    required this.partnerWord,
    required this.kind,
    required this.controller,
  });

  final String otherUserId;

  /// "Runner" or "Witness", for the "ask your … to add theirs" line.
  final String partnerWord;
  final MeetingKind kind;
  final TextEditingController controller;

  @override
  State<MidwaySpotSuggestions> createState() => _MidwaySpotSuggestionsState();
}

class _MidwaySpotSuggestionsState extends State<MidwaySpotSuggestions> {
  MidwaySuggestion? _result;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _fetch();
  }

  @override
  void didUpdateWidget(MidwaySpotSuggestions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
    if (oldWidget.kind != widget.kind || oldWidget.otherUserId != widget.otherUserId) _fetch();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  /// The chips track what is in the field.
  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _fetch() async {
    if (!widget.kind.suggestsPlace) {
      setState(() => _result = null);
      return;
    }
    final kind = widget.kind;
    setState(() => _loading = true);
    final result = await MeetingSpotService.instance.suggest(widget.otherUserId, kind);
    if (!mounted || kind != widget.kind) return;
    setState(() {
      _result = result;
      _loading = false;
    });
    if (result.status == MidwayStatus.found && widget.controller.text.trim().isEmpty) {
      widget.controller.text = result.places.first.label;
    }
  }

  void _use(PlaceSuggestion place) {
    widget.controller.text = place.label;
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final quiet = textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic);

    if (_loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            const BookplateSpinner(size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Looking for a ${widget.kind.placeNoun} midway…', style: quiet),
            ),
          ],
        ),
      );
    }

    final result = _result;
    if (result == null) return const SizedBox.shrink();

    switch (result.status) {
      case MidwayStatus.unavailable:
        return const SizedBox.shrink();
      case MidwayStatus.missingMe:
      case MidwayStatus.missingOther:
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Add your home or work under Meeting Places (and ask your ${widget.partnerWord} '
            'to add theirs) and The Trellis will suggest a spot midway.',
            style: quiet,
          ),
        );
      case MidwayStatus.nothingNearby:
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'No ${widget.kind.placeNoun} turned up midway between you — type one in.',
            style: quiet,
          ),
        );
      case MidwayStatus.found:
        final current = widget.controller.text.trim();
        final alternates =
            result.places.where((p) => p.label != current).take(2).toList(growable: false);
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (alternates.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final place in alternates)
                      Semantics(
                        label: 'Use ${place.label}',
                        button: true,
                        excludeSemantics: true,
                        onTap: () => _use(place),
                        child: BookplateChip(
                          label: place.name,
                          compact: true,
                          selected: false,
                          onTap: () => _use(place),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              Text('Suggested midway between you — tap to change', style: quiet),
            ],
          ),
        );
    }
  }
}
