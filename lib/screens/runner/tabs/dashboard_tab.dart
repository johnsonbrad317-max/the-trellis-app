import 'package:flutter/material.dart';

import '../../../models/runner_profile.dart';
import '../dashboard_screen.dart';

class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  Widget build(BuildContext context) => DashboardScreen(profile: profile);
}
