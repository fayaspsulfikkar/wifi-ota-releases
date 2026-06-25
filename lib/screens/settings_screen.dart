import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../providers/update_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _hapticEnabled = true;
  bool _autoOffEnabled = false;
  bool _muteOnExit = true;
  
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    // Check for updates automatically when entering settings
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(updateProvider.notifier).checkForUpdate();
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hapticEnabled = prefs.getBool('hapticEnabled') ?? true;
      _autoOffEnabled = prefs.getBool('autoOffEnabled') ?? false;
      _muteOnExit = prefs.getBool('muteOnBackground') ?? true;
    });
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  void _triggerHaptic() {
    if (_hapticEnabled) {
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _openBatterySettings() async {
    _triggerHaptic();
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final intent = AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:${packageInfo.packageName}',
      );
      await intent.launch();
    } catch (e) {
      // Fallback if specific app details doesn't work
      try {
        final intent = AndroidIntent(
          action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
        );
        await intent.launch();
      } catch (_) {
        _showTacticalSnackbar('SYSTEM ACCESS DENIED', isError: true);
      }
    }
  }

  Future<void> _downloadAndInstallUpdate(String apkUrl, String version) async {
    setState(() { _isDownloading = true; _downloadProgress = 0.0; });
    
    try {
      final dir = await getTemporaryDirectory();
      final safeVersion = version.replaceAll('+', '_');
      final savePath = '${dir.path}/update_$safeVersion.apk';
      final tempPath = '$savePath.tmp';
      
      final file = File(savePath);
      if (await file.exists()) {
        final result = await OpenFilex.open(savePath);
        if (result.type != ResultType.done) {
            await file.delete();
            _showTacticalSnackbar('CORRUPTED PAYLOAD. RETRYING.', isError: true);
        }
        return;
      }
      
      final dio = Dio();
      await dio.download(
        apkUrl,
        tempPath,
        onReceiveProgress: (received, total) {
          if (total != -1 && mounted) {
            setState(() { _downloadProgress = received / total; });
          }
        },
      );
      
      // Atomic rename
      final tempFile = File(tempPath);
      await tempFile.rename(savePath);
      
      final result = await OpenFilex.open(savePath);
      if (result.type != ResultType.done) {
          await file.delete();
          _showTacticalSnackbar('INSTALLATION REJECTED BY OS', isError: true);
      } else {
          _showTacticalSnackbar('PAYLOAD SECURED. EXECUTING.', isError: false);
      }
      
    } catch (e) {
      debugPrint("Download failed: $e");
      _showTacticalSnackbar('DOWNLOAD FAILED: CONNECTION LOST', isError: true);
    } finally {
      if (mounted) {
        setState(() { _isDownloading = false; });
      }
    }
  }

  void _showTacticalSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.black,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: isError ? const Color(0xFFFF5252) : const Color(0xFF00FF41),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildTacticalToggle({required String label, required String subtitle, required bool value, required ValueChanged<bool> onChanged}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161A1D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'monospace')),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'monospace')),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF00FF41),
            activeTrackColor: const Color(0xFF00FF41).withValues(alpha: 0.3),
            inactiveThumbColor: Colors.grey,
            inactiveTrackColor: Colors.white12,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0C0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161A1D),
        elevation: 0,
        title: const Text('SYSTEM SETTINGS', style: TextStyle(color: Colors.white, fontFamily: 'monospace', letterSpacing: 2)),
        iconTheme: const IconThemeData(color: Colors.white54),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(color: Colors.white12, height: 2),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'HARDWARE CONTROLS',
              style: TextStyle(color: Color(0xFF00E676), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 16),
            
            _buildTacticalToggle(
              label: 'VIBRATION FEEDBACK',
              subtitle: 'Tactile response for hardware events',
              value: _hapticEnabled,
              onChanged: (val) {
                setState(() => _hapticEnabled = val);
                _saveSetting('hapticEnabled', val);
                if (val) HapticFeedback.lightImpact();
              },
            ),

            _buildTacticalToggle(
              label: 'AUTO-OFF TIMER',
              subtitle: 'Power down LED after 10m of inactivity',
              value: _autoOffEnabled,
              onChanged: (val) {
                setState(() => _autoOffEnabled = val);
                _saveSetting('autoOffEnabled', val);
                _triggerHaptic();
              },
            ),

            _buildTacticalToggle(
              label: 'BACKGROUND ACOUSTIC DAMPENING',
              subtitle: 'Silence acoustic output when minimized',
              value: _muteOnExit,
              onChanged: (val) {
                setState(() => _muteOnExit = val);
                _saveSetting('muteOnBackground', val);
                _triggerHaptic();
              },
            ),

            const SizedBox(height: 24),
            const Text(
              'SYSTEM OPTIMIZATION',
              style: TextStyle(color: Color(0xFF00E676), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 16),

            InkWell(
              onTap: _openBatterySettings,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF161A1D),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12, width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.battery_charging_full_rounded, color: Colors.white54),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('PWR OPTIMIZATION', style: TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'monospace')),
                          SizedBox(height: 4),
                          Text('Configure OS background power limits', style: TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'monospace')),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white54),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),
            const Text(
              'FIRMWARE',
              style: TextStyle(color: Color(0xFF00E676), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161A1D),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12, width: 1),
              ),
              child: Consumer(
                builder: (context, ref, child) {
                  final updateState = ref.watch(updateProvider);
                  
                  return Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('CURRENT BUILD', style: TextStyle(color: Colors.white54, fontFamily: 'monospace')),
                          Text(updateState.currentVersion ?? "...", style: const TextStyle(color: Colors.white, fontFamily: 'monospace')),
                        ],
                      ),
                      const SizedBox(height: 20),
                      
                      if (_isDownloading) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('DOWNLOADING PAYLOAD...', style: TextStyle(color: Color(0xFF64B5F6), fontFamily: 'monospace', fontSize: 12)),
                            Text('${(_downloadProgress * 100).toStringAsFixed(0)}%', style: const TextStyle(color: Color(0xFF64B5F6), fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: _downloadProgress,
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF64B5F6)),
                            minHeight: 6,
                          ),
                        ),
                      ] else if (updateState.isChecking) ...[
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: null,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white12),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            ),
                            child: const Text('SCANNING FOR UPDATES...', style: TextStyle(color: Colors.white54, fontFamily: 'monospace', letterSpacing: 1)),
                          ),
                        ),
                      ] else if (updateState.updateAvailable && updateState.apkUrl != null) ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              _triggerHaptic();
                              _downloadAndInstallUpdate(updateState.apkUrl!, updateState.latestVersion!);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00FF41),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            ),
                            child: const Text('EXECUTE UPDATE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: 1)),
                          ),
                        ),
                      ] else ...[
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () {
                              _triggerHaptic();
                              ref.read(updateProvider.notifier).checkForUpdate();
                            },
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF00E676)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            ),
                            child: const Text('CHECK FOR UPDATES', style: TextStyle(color: Color(0xFF00E676), fontFamily: 'monospace', letterSpacing: 1)),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
