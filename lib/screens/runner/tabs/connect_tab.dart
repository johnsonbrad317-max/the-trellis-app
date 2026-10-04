import 'package:flutter/material.dart';

import '../../../models/runner_profile.dart';
import '../connect_screen.dart';

class ConnectTab extends StatelessWidget {
  const ConnectTab({super.key, required this.profile});

  final RunnerProfile profile;

  @override
  Widget build(BuildContext context) => ConnectScreen(profile: profile);
}
