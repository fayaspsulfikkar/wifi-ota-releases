/// Settings provider for persisting local app preferences.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Keys
const _kAudioRoute = 'settings_audio_route';
const _kEchoCancellation = 'settings_echo_cancellation';
const _kNoiseSuppression = 'settings_noise_suppression';
const _kAutoMuteMic = 'settings_auto_mute_mic';
const _kAutoMuteSpeakers = 'settings_auto_mute_speakers';

/// The SharedPreferences instance, initialized in main.dart
final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Initialize this in main() using overrideWithValue');
});

/// A state notifier that manages all settings and persists them.
class SettingsNotifier extends StateNotifier<SettingsState> {
  final SharedPreferences _prefs;

  SettingsNotifier(this._prefs) : super(_loadInitialState(_prefs));

  static SettingsState _loadInitialState(SharedPreferences prefs) {
    return SettingsState(
      audioRoute: prefs.getString(_kAudioRoute) ?? 'speaker',
      echoCancellation: prefs.getBool(_kEchoCancellation) ?? true,
      noiseSuppression: prefs.getBool(_kNoiseSuppression) ?? true,
      autoMuteMic: prefs.getBool(_kAutoMuteMic) ?? false,
      autoMuteSpeakers: prefs.getBool(_kAutoMuteSpeakers) ?? false,
    );
  }

  void _reload() {
    state = _loadInitialState(_prefs);
  }

  Future<void> updateAudioRoute(String route) async {
    await _prefs.setString(_kAudioRoute, route);
    _reload();
  }

  Future<void> updateEchoCancellation(bool value) async {
    await _prefs.setBool(_kEchoCancellation, value);
    _reload();
  }

  Future<void> updateNoiseSuppression(bool value) async {
    await _prefs.setBool(_kNoiseSuppression, value);
    _reload();
  }

  Future<void> updateAutoMuteMic(bool value) async {
    await _prefs.setBool(_kAutoMuteMic, value);
    _reload();
  }

  Future<void> updateAutoMuteSpeakers(bool value) async {
    await _prefs.setBool(_kAutoMuteSpeakers, value);
    _reload();
  }
}

class SettingsState {
  final String audioRoute;
  final bool echoCancellation;
  final bool noiseSuppression;
  final bool autoMuteMic;
  final bool autoMuteSpeakers;

  const SettingsState({
    required this.audioRoute,
    required this.echoCancellation,
    required this.noiseSuppression,
    required this.autoMuteMic,
    required this.autoMuteSpeakers,
  });
}

/// Provider that returns the SettingsState directly.
final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier(ref.watch(sharedPrefsProvider));
});
