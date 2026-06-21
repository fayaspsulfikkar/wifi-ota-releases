import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

class UpdateState {
  final bool isChecking;
  final String? currentVersion;
  final String? latestVersion;
  final String? apkUrl;

  bool get updateAvailable {
    if (currentVersion == null || latestVersion == null) return false;
    return currentVersion != latestVersion;
  }

  UpdateState({
    this.isChecking = false,
    this.currentVersion,
    this.latestVersion,
    this.apkUrl,
  });

  UpdateState copyWith({
    bool? isChecking,
    String? currentVersion,
    String? latestVersion,
    String? apkUrl,
  }) {
    return UpdateState(
      isChecking: isChecking ?? this.isChecking,
      currentVersion: currentVersion ?? this.currentVersion,
      latestVersion: latestVersion ?? this.latestVersion,
      apkUrl: apkUrl ?? this.apkUrl,
    );
  }
}

class UpdateNotifier extends StateNotifier<UpdateState> {
  UpdateNotifier() : super(UpdateState()) {
    _init();
  }

  Future<void> _init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = 'v${info.version}.${info.buildNumber}';
      state = state.copyWith(currentVersion: version);
      checkForUpdate();
    } catch (_) {}
  }

  Future<void> checkForUpdate() async {
    if (state.isChecking) return;
    state = state.copyWith(isChecking: true);
    try {
      final dio = Dio();
      final response = await dio.get('https://api.github.com/repos/fayaspsulfikkar/wifi-ota-releases/releases/latest');
      if (response.statusCode == 200) {
        final data = response.data;
        final latestTag = data['tag_name'];
        final assets = data['assets'] as List;
        String? downloadUrl;
        if (assets.isNotEmpty) {
          downloadUrl = assets[0]['browser_download_url'];
        }
        state = state.copyWith(latestVersion: latestTag, apkUrl: downloadUrl);
      }
    } catch(e) {
      // Check failed silently
    } finally {
      state = state.copyWith(isChecking: false);
    }
  }
}

final updateProvider = StateNotifierProvider<UpdateNotifier, UpdateState>((ref) {
  return UpdateNotifier();
});
