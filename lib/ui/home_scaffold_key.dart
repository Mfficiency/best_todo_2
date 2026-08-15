import 'package:flutter/material.dart';

final GlobalKey<ScaffoldState> homeScaffoldKey = GlobalKey<ScaffoldState>();

/// Set by the home page while it is mounted: reopens the dice timer page for
/// the timer that is currently live, and does nothing when there is none.
/// Used after a full-screen dice-timer alarm is stopped, so the rolled task's
/// Done / Postpone / +min actions are right there.
VoidCallback? openRunningDiceTimer;
