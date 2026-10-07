import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../models/user_role.dart';
import 'cloud_shell.dart';
import 'runner/choose_rule_screen.dart';
import 'runner_shell.dart';
import 'witness/witness_pairing_code_screen.dart';
import 'witness_shell.dart';

/// Where a person lands once they have chosen how to start (the last slide of
/// the welcome deck), with the first sensible step already open:
///
///   * Runner  → the Rule of Life tab, with "Let's create your Rule of Life"
///               on top (unless they already have rhythms of their own);
///   * Witness → the Witness view, with the pairing-key screen on top (unless
///               they already walk with someone);
///   * Cloud   → the Cloud view (the access code has been redeemed by then).
///
/// Everything before it is cleared, so Back never returns to the deck or to
/// sign-up.
void startJourney(NavigatorState navigator, RunnerProfile profile, UserRole role) {
  switch (role) {
    case UserRole.runner:
      if (profile.role != UserRole.runner) profile.setRole(UserRole.runner);
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => RunnerShell(profile: profile, initialTab: RunnerTab.ruleOfLife),
        ),
        (route) => false,
      );
      if (!hasOwnRule(profile)) {
        navigator.push(
          MaterialPageRoute(builder: (context) => ChooseRuleScreen(profile: profile)),
        );
      }
    case UserRole.witness:
      if (profile.role != UserRole.witness) profile.setRole(UserRole.witness);
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => WitnessShell(profile: profile)),
        (route) => false,
      );
      if (profile.watchedRunners.isEmpty) {
        navigator.push(
          MaterialPageRoute(builder: (context) => WitnessPairingCodeScreen(profile: profile)),
        );
      }
    case UserRole.cloud:
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => CloudShell(profile: profile)),
        (route) => false,
      );
  }
}

/// Into the app with no first step: the shell for the role the account
/// already has (used when the deck is skipped).
void enterApp(NavigatorState navigator, RunnerProfile profile) {
  navigator.pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (context) => profile.role == UserRole.witness
          ? WitnessShell(profile: profile)
          : RunnerShell(profile: profile),
    ),
    (route) => false,
  );
}
