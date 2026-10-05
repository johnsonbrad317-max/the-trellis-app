import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme/app_colors.dart';
import 'bookplate_plate.dart';
import 'brass_glyph.dart';

/// One Places (New) Autocomplete suggestion.
class _PlacePrediction {
  const _PlacePrediction({required this.text, required this.mainText, required this.secondaryText});

  factory _PlacePrediction.fromJson(Map<String, dynamic> json) {
    final structured = json['structuredFormat'] as Map<String, dynamic>?;
    final text = (json['text'] as Map<String, dynamic>?)?['text'] as String? ?? '';
    final mainText =
        (structured?['mainText'] as Map<String, dynamic>?)?['text'] as String? ?? text;
    final secondaryText =
        (structured?['secondaryText'] as Map<String, dynamic>?)?['text'] as String? ?? '';
    return _PlacePrediction(text: text, mainText: mainText, secondaryText: secondaryText);
  }

  final String text;
  final String mainText;
  final String secondaryText;
}

/// A Google Places (New) Autocomplete-backed location field: as the user
/// types a real-world location, a dropdown of matching place predictions
/// appears below the field; selecting one fills in that place's full
/// formatted name/address, so an actual, geocodable location — not a vague
/// hand-typed description — is what ends up on the meeting and its
/// calendar invite.
///
/// TODO(api-key): [apiKey] must be supplied with a real Google Cloud
/// Places API key (Places API (New) enabled, with an HTTP referrer
/// restriction matching this app's domain) for live suggestions —
/// e.g. build with `--dart-define=GOOGLE_PLACES_API_KEY=your-key-here`.
/// Without a key, this degrades gracefully to a plain, fully usable text
/// field: typing still works, there's just no autocomplete dropdown.
class PlacesAutocompleteField extends StatefulWidget {
  const PlacesAutocompleteField({
    super.key,
    required this.controller,
    this.apiKey = const String.fromEnvironment('GOOGLE_PLACES_API_KEY'),
    this.labelText = 'Location',
    this.hintText = 'e.g. The Roasterie on Main St',
    this.errorText,
  });

  final TextEditingController controller;
  final String apiKey;
  final String labelText;
  final String hintText;
  final String? errorText;

  @override
  State<PlacesAutocompleteField> createState() => _PlacesAutocompleteFieldState();
}

class _PlacesAutocompleteFieldState extends State<PlacesAutocompleteField> {
  Timer? _debounce;
  List<_PlacePrediction> _predictions = [];
  bool _isLoading = false;

  bool get _hasApiKey => widget.apiKey.isNotEmpty;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (!_hasApiKey || value.trim().length < 3) {
      setState(() => _predictions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _fetchPredictions(value));
  }

  Future<void> _fetchPredictions(String input) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('https://places.googleapis.com/v1/places:autocomplete'),
        headers: {'Content-Type': 'application/json', 'X-Goog-Api-Key': widget.apiKey},
        body: jsonEncode({'input': input}),
      );

      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() => _predictions = []);
        return;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final suggestions = body['suggestions'] as List<dynamic>? ?? [];
      setState(() {
        _predictions = [
          for (final suggestion in suggestions)
            if ((suggestion as Map<String, dynamic>)['placePrediction'] != null)
              _PlacePrediction.fromJson(
                suggestion['placePrediction'] as Map<String, dynamic>,
              ),
        ];
      });
    } catch (_) {
      // A network hiccup, an unconfigured/invalid key, or (on web) a CORS
      // rejection — degrade silently to a plain text field rather than
      // interrupting the meeting-scheduling flow with an error dialog.
      if (mounted) setState(() => _predictions = []);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _select(_PlacePrediction prediction) {
    widget.controller.text = prediction.text;
    setState(() => _predictions = []);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          textCapitalization: TextCapitalization.words,
          onChanged: _onChanged,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            errorText: widget.errorText,
            suffixIcon: Padding(
              padding: const EdgeInsets.all(14),
              child: _isLoading
                  ? const BookplateSpinner(size: 20)
                  : const BrassGlyph(BrassGlyphKind.pin, size: 20, color: AppColors.antiqueBrass),
            ),
          ),
        ),
        if (_predictions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: AppColors.vellum,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.vellumBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _predictions.length; i++) ...[
                  if (i > 0) const BookplateDivider(),
                  _PredictionRow(
                    prediction: _predictions[i],
                    onTap: () => _select(_predictions[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// One tappable suggestion: a brass pin, the place's name, and (when Google
/// supplies one) its locality beneath.
class _PredictionRow extends StatelessWidget {
  const _PredictionRow({required this.prediction, required this.onTap});

  final _PlacePrediction prediction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: prediction.text,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                const BrassGlyph(BrassGlyphKind.pin, size: 18, color: AppColors.antiqueBrass),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(prediction.mainText, style: textTheme.bodyMedium),
                      if (prediction.secondaryText.isNotEmpty)
                        Text(prediction.secondaryText, style: textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
