/// Audio state providers for microphone and listening controls.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mic state (true = on, false = off).
final micStateProvider = StateProvider<bool>((ref) => true);

/// Listening state (HEAR button: true = on, false = off).
final listeningStateProvider = StateProvider<bool>((ref) => true);
