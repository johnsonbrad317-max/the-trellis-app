import 'package:flutter/material.dart';

import '../models/runner_profile.dart';
import '../models/user_role.dart';
import 'runner_shell.dart';
import 'witness_shell.dart';

/// The shell a signed-in account should land in: the Witness view if that's
/// the view it last had selected (`profiles.role`, persisted through the
/// `set_my_role` RPC), otherwise the Runner view. Cloud is never a stored
/// role, so it's never an answer here — a Cloud admin lands in their last
/// Runner/Witness view and switches to Cloud from the role switcher.
Widget shellForProfile(RunnerProfile profile) =>
    profile.role == UserRole.witness ? WitnessShell(profile: profile) : RunnerShell(profile: profile);
