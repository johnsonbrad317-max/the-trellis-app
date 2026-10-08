import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/models/membership_gate.dart';
import 'package:trellis/models/runner_profile.dart';
import 'package:trellis/models/user_role.dart';
import 'package:trellis/screens/runner/membership_gate_page.dart';
import 'package:trellis/theme/app_theme.dart';

/// The membership gate (supabase/migrations/029_membership_gate.sql): two free
/// weeks, then the Runner view asks for a subscription, a church/organization
/// code or a gift membership — but only once the launch switch is on, and never for
/// the Witness or the Cloud.
void main() {
  final serverNow = DateTime.utc(2026, 11, 1, 12);
  final trialOver = serverNow.subtract(const Duration(days: 1));
  final trialRunning = serverNow.add(const Duration(days: 5));

  /// What `my_membership()` returns, with the given overrides.
  Map<String, Object?> payload({
    bool enforce = true,
    bool needs = true,
    String status = 'trial',
    DateTime? trialEndsAt,
    DateTime? paidUntil,
    bool churchMember = false,
  }) =>
      {
        'status': status,
        'trial_ends_at': (trialEndsAt ?? trialOver).toIso8601String(),
        'paid_until': paidUntil?.toIso8601String(),
        'enforce': enforce,
        'needs_membership': needs,
        'church_member': churchMember,
        'now': serverNow.toIso8601String(),
      };

  group('MembershipGate.fromJson', () {
    test('reads every field of my_membership()', () {
      final paid = serverNow.add(const Duration(days: 300));
      final gate = MembershipGate.fromJson(
        payload(status: 'active', needs: false, paidUntil: paid, churchMember: true),
      );
      expect(gate.enforced, isTrue);
      expect(gate.needsMembership, isFalse);
      expect(gate.status, 'active');
      expect(gate.trialEndsAt, trialOver);
      expect(gate.paidUntil, paid);
      expect(gate.churchMember, isTrue);
      expect(gate.serverNow, serverNow);
    });

    test('an absent RPC or a garbled answer is "not enforced"', () {
      for (final garbage in <Object?>[
        null,
        'nope',
        42,
        const [1, 2, 3],
        const <String, Object?>{},
        {'enforce': 'yes', 'needs_membership': true},
        {'enforce': true},
        {'needs_membership': true},
        {'enforce': true, 'needs_membership': 'true'},
      ]) {
        final gate = MembershipGate.fromJson(garbage);
        expect(gate.enforced, isFalse, reason: '$garbage');
        expect(gate.needsMembership, isFalse, reason: '$garbage');
        expect(gate.gates(UserRole.runner), isFalse, reason: '$garbage');
        expect(gate.isTrialPeriodAt(serverNow), isFalse, reason: '$garbage');
      }
    });

    test('a bad date is simply unknown', () {
      final gate = MembershipGate.fromJson({
        ...payload(),
        'trial_ends_at': 'someday',
        'paid_until': 17,
        'now': null,
      });
      expect(gate.trialEndsAt, isNull);
      expect(gate.paidUntil, isNull);
      expect(gate.serverNow, isNull);
    });

    test('needs_membership never stands while the switch is off', () {
      final gate = MembershipGate.fromJson(payload(enforce: false, needs: true));
      expect(gate.needsMembership, isFalse);
    });
  });

  group('who is gated', () {
    bool gated(Map<String, Object?> json, [UserRole role = UserRole.runner]) =>
        MembershipGate.fromJson(json).gates(role);

    test('switch off: never', () {
      expect(gated(payload(enforce: false)), isFalse);
      expect(gated(payload(enforce: false, needs: true, status: 'cancelled')), isFalse);
    });

    test('Witness and Cloud: never', () {
      expect(gated(payload(), UserRole.witness), isFalse);
      expect(gated(payload(), UserRole.cloud), isFalse);
    });

    test('a membership in hand: never', () {
      expect(gated(payload(status: 'active')), isFalse, reason: 'store or church code');
      expect(gated(payload(paidUntil: serverNow.add(const Duration(days: 30)))), isFalse,
          reason: 'gift time left');
      expect(gated(payload(churchMember: true)), isFalse, reason: 'church seat');
      expect(gated(payload(needs: false)), isFalse, reason: "the server's own verdict");
    });

    test('trial still running: never', () {
      expect(gated(payload(trialEndsAt: trialRunning)), isFalse);
    });

    test('trial over and nothing else: gated', () {
      expect(gated(payload()), isTrue);
      expect(gated(payload(status: 'cancelled')), isTrue, reason: 'subscription lapsed');
      expect(
        gated(payload(status: 'active', paidUntil: serverNow.subtract(const Duration(days: 1)))),
        isTrue,
        reason: 'gift time ran out',
      );
    });

    test('the trial is judged by the server clock, not the phone', () {
      // Even with a phone clock set back, the server said the trial is over.
      final gate = MembershipGate.fromJson(payload());
      expect(gate.gates(UserRole.runner), isTrue);
    });
  });

  group('trial wording', () {
    test('shown only while the switch is on and the trial runs', () {
      final running = MembershipGate.fromJson(payload(needs: false, trialEndsAt: trialRunning));
      expect(running.isTrialPeriodAt(serverNow), isTrue);
      expect(running.isTrialPeriodAt(trialRunning.add(const Duration(minutes: 1))), isFalse);

      final switchedOff = MembershipGate.fromJson(
        payload(enforce: false, needs: false, trialEndsAt: trialRunning),
      );
      expect(switchedOff.isTrialPeriodAt(serverNow), isFalse);

      final member = MembershipGate.fromJson(
        payload(status: 'active', needs: false, trialEndsAt: trialRunning),
      );
      expect(member.isTrialPeriodAt(serverNow), isFalse);
    });

    test('dates read the way people write them', () {
      expect(formatMembershipDate(DateTime(2026, 10, 21)), 'October 21, 2026');
    });
  });

  group('RunnerProfile', () {
    test('is never gated before my_membership() has said otherwise', () {
      final profile = RunnerProfile.preview();
      expect(profile.membershipGate.enforced, isFalse);
      expect(profile.needsMembership, isFalse);
      expect(profile.isTrialPeriod, isFalse);
    });

    test('gates only the Runner view', () {
      final profile = RunnerProfile.preview()..membershipGate = MembershipGate.fromJson(payload());
      expect(profile.role, UserRole.runner);
      expect(profile.needsMembership, isTrue);

      profile.setRole(UserRole.witness);
      expect(profile.needsMembership, isFalse);
    });

    test('a purchase on this phone lifts the gate at once', () {
      final profile = RunnerProfile.preview()..membershipGate = MembershipGate.fromJson(payload());
      expect(profile.needsMembership, isTrue);
      profile.applyLocalMembershipStatus(MembershipStatus.active);
      expect(profile.needsMembership, isFalse);
    });
  });

  group('MembershipGatePage', () {
    testWidgets('offers the three ways in and the free Witness view', (tester) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var switched = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MembershipGatePage(
            profile: RunnerProfile.preview(),
            onSwitchToWitness: () => switched++,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Your two free weeks are over'), findsOneWidget);
      expect(find.textContaining('Keep going as a Runner with one of these:'), findsOneWidget);
      expect(find.text('Subscribe — \$12 a year'), findsOneWidget);
      expect(find.text('Enter a church or organization code'), findsOneWidget);
      expect(find.text('Check again'), findsOneWidget);
      expect(find.textContaining('gift code'), findsNothing);
      expect(find.text('Witnessing is always free.'), findsOneWidget);

      final witnessLink = find.text('Switch to Witness');
      await tester.ensureVisible(witnessLink);
      await tester.pumpAndSettle();
      await tester.tap(witnessLink);
      await tester.pump();
      expect(switched, 1);
    });
  });
}
