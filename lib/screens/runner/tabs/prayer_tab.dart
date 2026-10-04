import 'package:flutter/material.dart';

import '../../../models/runner_profile.dart';
import '../prayer_garden_screen.dart';

class PrayerTab extends StatelessWidget {
  const PrayerTab({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  Widget build(BuildContext context) => PrayerGardenScreen(profile: profile);
}
