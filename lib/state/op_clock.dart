import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The wall clock long-operation timing reads. A provider so tests can move
/// time by hand instead of sleeping.
final opClockProvider = Provider<DateTime Function()>((_) => DateTime.now);
