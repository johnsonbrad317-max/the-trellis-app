/// A Witness holding a Runner accountable — read-only from the Runner's side
/// except for removal, which the accountability lock may gate.
class Witness {
  const Witness({required this.id, required this.name, required this.since});

  /// [row] is a `witness_pairings` row with an embedded
  /// `witness:profiles!witness_id(id, name)` select — see
  /// RunnerProfile.loadRunnerData's witnesses query.
  factory Witness.fromRow(Map<String, dynamic> row) {
    final witnessProfile = row['witness'] as Map<String, dynamic>;
    return Witness(
      id: witnessProfile['id'] as String,
      name: witnessProfile['name'] as String,
      since: DateTime.parse(row['paired_since'] as String),
    );
  }

  final String id;
  final String name;
  final DateTime since;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    // By code point, not UTF-16 unit: `substring(0, 1)` would cut an emoji or
    // other astral character in half and render a broken glyph.
    String initial(String word) => String.fromCharCode(word.runes.first).toUpperCase();
    if (parts.length == 1) return initial(parts.first);
    return initial(parts.first) + initial(parts.last);
  }
}
