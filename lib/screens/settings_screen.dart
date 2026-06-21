import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../core/constants.dart';
import '../core/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/webrtc_provider.dart';
import '../providers/presence_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/update_provider.dart';
import '../services/foreground_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  Future<void> _downloadAndInstallUpdate() async {
    final updateState = ref.read(updateProvider);
    if (updateState.apkUrl == null || updateState.latestVersion == null) return;
    HapticFeedback.mediumImpact();
    setState(() { _isDownloading = true; _downloadProgress = 0.0; });
    
    try {
      final dir = await getTemporaryDirectory();
      final safeVersion = updateState.latestVersion!.replaceAll('+', '_');
      final savePath = '${dir.path}/update_$safeVersion.apk';
      
      if (await File(savePath).exists()) {
        await OpenFilex.open(savePath);
      } else {
        final dio = Dio();
        await dio.download(
          updateState.apkUrl!,
          savePath,
          onReceiveProgress: (received, total) {
            if (total != -1 && mounted) {
              setState(() {
                _downloadProgress = received / total;
              });
            }
          },
        );
        await OpenFilex.open(savePath);
      }
    } catch (e) {
      debugPrint("Download failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed.'), backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) {
        setState(() { _isDownloading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final user = ref.watch(currentUserProvider).value;
    final updateState = ref.watch(updateProvider);

    return GradientScaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          children: [
            // ─── Header ─────────────────────────────────────────
            Row(
              children: [
                GlassIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  size: 44,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const Expanded(
                  child: Center(
                    child: Text('Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  ),
                ),
                const SizedBox(width: 44), // To keep title centered
              ],
            ),
            const SizedBox(height: 32),

            // ─── Profile ──────────────────────────────────────
            const SectionHeader(title: 'Account'),
          GlassPanel(
            padding: EdgeInsets.zero,
            borderRadius: 16,
            child: _SettingsTile(
              icon: Icons.person_rounded,
              iconColor: AppColors.accent,
              title: user?.username ?? 'Unknown',
              subtitle: 'Current alias',
            ),
          ),

          const SizedBox(height: 24),

          // ─── OPSEC ────────────────────────────────────────
          const SectionHeader(title: 'Preferences'),
          GlassPanel(
            padding: EdgeInsets.zero,
            borderRadius: 16,
            child: Column(
              children: [
                _SettingsSwitch(
                  icon: Icons.mic_off_rounded,
                  iconColor: AppColors.accent,
                  title: 'Auto-mute Mic on Join',
                  subtitle: 'Start with microphone disabled',
                  value: settings.autoMuteMic,
                  onChanged: (val) {
                    HapticFeedback.selectionClick();
                    ref.read(settingsProvider.notifier).updateAutoMuteMic(val);
                  },
                ),
                Container(height: 1, color: AppColors.glassBorder),
                _SettingsSwitch(
                  icon: Icons.volume_off_rounded,
                  iconColor: AppColors.accent,
                  title: 'Mute Speakers on Quit',
                  subtitle: 'Silence incoming audio when app is closed',
                  value: settings.autoMuteSpeakers,
                  onChanged: (val) {
                    HapticFeedback.selectionClick();
                    ref.read(settingsProvider.notifier).updateAutoMuteSpeakers(val);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ─── Audio ────────────────────────────────────────
          const SectionHeader(title: 'Audio'),
          GlassPanel(
            padding: EdgeInsets.zero,
            borderRadius: 16,
            child: Column(
              children: [
                _SettingsSwitch(
                  icon: Icons.surround_sound_rounded,
                  iconColor: AppColors.accent,
                  title: 'Echo Cancellation',
                  subtitle: 'Reduce acoustic echo (Reconnect to apply)',
                  value: settings.echoCancellation,
                  onChanged: (val) {
                    HapticFeedback.selectionClick();
                    ref.read(settingsProvider.notifier).updateEchoCancellation(val);
                  },
                ),
                Container(height: 1, color: AppColors.glassBorder),
                _SettingsSwitch(
                  icon: Icons.noise_aware_rounded,
                  iconColor: AppColors.accent,
                  title: 'Noise Suppression',
                  subtitle: 'Filter out background noise (Reconnect to apply)',
                  value: settings.noiseSuppression,
                  onChanged: (val) {
                    HapticFeedback.selectionClick();
                    ref.read(settingsProvider.notifier).updateNoiseSuppression(val);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ─── Battery ──────────────────────────────────────
          const SectionHeader(title: 'System'),
          GlassPanel(
            padding: EdgeInsets.zero,
            borderRadius: 16,
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.battery_saver_rounded,
                  iconColor: AppColors.accent,
                  title: 'Ignore Battery Optimization',
                  subtitle: 'Keep app running in background',
                  onTap: () => _openBatterySettings(context),
                ),
                Container(height: 1, color: AppColors.glassBorder),
                _SettingsTile(
                  icon: Icons.delete_sweep_rounded,
                  iconColor: AppColors.danger,
                  titleColor: AppColors.danger,
                  title: 'Clear Local Cache',
                  subtitle: 'Purge temp files and OTA downloads',
                  onTap: () async {
                    HapticFeedback.mediumImpact();
                    final dir = await getTemporaryDirectory();
                    if (dir.existsSync()) {
                      dir.deleteSync(recursive: true);
                      dir.createSync();
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: const Text('Cache Purged'), backgroundColor: AppColors.success),
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ─── About ────────────────────────────────────────
          const SectionHeader(title: 'About'),
          GlassPanel(
            padding: EdgeInsets.zero,
            borderRadius: 16,
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.info_outline_rounded,
                  iconColor: AppColors.textSecondary,
                  title: 'Version',
                  subtitle: updateState.currentVersion ?? 'Loading...',
                ),
                Container(height: 1, color: AppColors.glassBorder),
                if (_isDownloading)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Downloading update...', style: AppTextStyles.label.copyWith(color: AppColors.accent)),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _downloadProgress,
                            backgroundColor: AppColors.accent.withOpacity(0.2),
                            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (updateState.updateAvailable && updateState.apkUrl != null)
                  _SettingsTile(
                    icon: Icons.system_update_rounded,
                    iconColor: AppColors.accent,
                    title: 'Update Available (${updateState.latestVersion})',
                    subtitle: 'Tap to download and install',
                    titleColor: AppColors.accent,
                    onTap: _downloadAndInstallUpdate,
                  )
                else
                  _SettingsTile(
                    icon: Icons.system_update_alt_rounded,
                    iconColor: AppColors.textSecondary,
                    title: 'Firmware Update',
                    subtitle: updateState.isChecking ? 'Checking for updates...' : 'Check for available OTA updates',
                    onTap: updateState.isChecking ? null : () {
                      HapticFeedback.lightImpact();
                      ref.read(updateProvider.notifier).checkForUpdate();
                    },
                  ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ─── Sign Out ─────────────────────────────────────
          GlassButton(
            label: 'Sign Out',
            onTap: () => _signOut(context, ref),
            color: AppColors.danger,
            filled: false,
            borderRadius: 16,
          ),

          const SizedBox(height: 40),
        ],
      ),
      ),
    );
  }

  Future<void> _openBatterySettings(BuildContext context) async {
    try {
      final intent = AndroidIntent(
        action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
      );
      await intent.launch();
    } catch (e) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.bgElevated,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Power Management', style: AppTextStyles.heading3),
            content: Text(
              'To keep connected in the background:\n\n'
              '1. Go to Settings → Apps → App Info\n'
              '2. Tap "Battery"\n'
              '3. Select "Unrestricted"\n\n'
              'This prevents the OS from closing the app.',
              style: AppTextStyles.body.copyWith(height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('OK', style: AppTextStyles.buttonText),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    HapticFeedback.heavyImpact();
    await ref.read(signalingServiceProvider).stopSignaling();
    await ref.read(webrtcServiceProvider).disposeAll();
    await ref.read(presenceServiceProvider).goOffline();
    await stopForegroundService();
    await ref.read(authServiceProvider).signOut();

    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
    }
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color? titleColor;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.titleColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.bodyMedium.copyWith(color: titleColor ?? AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTextStyles.caption),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitch({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodyMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTextStyles.caption),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.textPrimary,
            activeTrackColor: AppColors.accent,
            inactiveThumbColor: AppColors.textSecondary,
            inactiveTrackColor: AppColors.bgElevated,
          ),
        ],
      ),
    );
  }
}
