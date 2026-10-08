import 'user_role.dart';

/// What the server's `my_membership()` (supabase/migrations/029) says about
/// this account: whether the membership gate is switched on at all, and
/// whether this person's Runner view would be behind it.
///
/// The pricing model: two free weeks from sign-up, then a Runner keeps going
/// with an App Store subscription, a church/organization code, or a gift membership
/// (redeemed on the website against the account email, never in the app).
/// Witnessing is always free and the Cloud is never gated, so the gate only
/// ever applies to [UserRole.runner].
///
/// Everything fails soft toward "not gated": an absent RPC, a garbled answer,
/// or the switch being off (`app_settings.enforce_membership = false`, the
/// state through the whole beta) all read as [notEnforced].
class MembershipGate {
  const MembershipGate({
    required this.enforced,
    required this.needsMembership,
    this.status,
    this.trialEndsAt,
    this.paidUntil,
    this.churchMember = false,
    this.serverNow,
  });

  /// The switch is off (or nothing could be read): nobody is gated, and no
  /// trial date is shown anywhere.
  static const notEnforced = MembershipGate(enforced: false, needsMembership: false);

  /// Parses `my_membership()`'s jsonb. Anything that isn't a map carrying
  /// boolean `enforce` and `needs_membership` is [notEnforced].
  factory MembershipGate.fromJson(Object? json) {
    if (json is! Map) return notEnforced;
    final enforce = json['enforce'];
    final needs = json['needs_membership'];
    if (enforce is! bool || needs is! bool) return notEnforced;
    final status = json['status'];
    return MembershipGate(
      enforced: enforce,
      needsMembership: enforce && needs,
      status: status is String ? status : null,
      trialEndsAt: _date(json['trial_ends_at']),
      paidUntil: _date(json['paid_until']),
      churchMember: json['church_member'] == true,
      serverNow: _date(json['now']),
    );
  }

  /// `app_settings.enforce_membership` — the launch switch.
  final bool enforced;

  /// The server's verdict for the Runner view (always false unless [enforced]).
  final bool needsMembership;

  /// `profiles.membership_status`: 'trial', 'active' or 'cancelled'.
  final String? status;

  /// When the free trial ends (or ended).
  final DateTime? trialEndsAt;

  /// Gift-code time: covered until this instant. Null = no gift.
  final DateTime? paidUntil;

  /// A member of a church, which holds a seat for them.
  final bool churchMember;

  /// The server's clock when this was read — used instead of the phone's,
  /// so changing the phone's date can't reopen a trial.
  final DateTime? serverNow;

  static DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value) : null;

  /// Covered by a membership of some kind, judged from the fields alone.
  bool isCoveredAt(DateTime now) {
    final paid = paidUntil;
    if (churchMember) return true;
    if (paid != null && paid.isAfter(now)) return true;
    return status == 'active' && paid == null;
  }

  /// Whether the Runner view for [role] is behind the gate. Only when the
  /// switch is on, the server says so, and nothing the server sent
  /// contradicts it (a membership in hand, or a trial still running by the
  /// server's own clock) — any doubt leaves the Runner in.
  bool gates(UserRole role) {
    if (role != UserRole.runner || !enforced || !needsMembership) return false;
    final now = serverNow;
    if (now == null) return true;
    if (isCoveredAt(now)) return false;
    final trialEnd = trialEndsAt;
    return trialEnd == null || !now.isBefore(trialEnd);
  }

  /// "Free trial — ends {date}" applies: the switch is on, there is no
  /// membership, and the trial hasn't ended yet. Always false while the switch
  /// is off, so the beta shows nothing about trial dates.
  bool isTrialPeriodAt(DateTime now) {
    final trialEnd = trialEndsAt;
    return enforced && trialEnd != null && now.isBefore(trialEnd) && !isCoveredAt(now);
  }
}

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// "October 21, 2026", in the phone's own time zone.
String formatMembershipDate(DateTime date) {
  final local = date.toLocal();
  return '${_monthNames[local.month - 1]} ${local.day}, ${local.year}';
}
