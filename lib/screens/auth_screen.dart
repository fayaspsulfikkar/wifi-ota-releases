/// Authentication screen — Liquid Glass design.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/app_theme.dart';
import '../providers/auth_provider.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.lightImpact();

    ref.read(authLoadingProvider.notifier).state = true;
    ref.read(authErrorProvider.notifier).state = null;

    try {
      final authService = ref.read(authServiceProvider);
      final username = _usernameController.text.trim();
      final password = _passwordController.text;

      await authService.signIn(username, password);

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      String errorMessage = e.toString();
      if (e is FirebaseAuthException) {
        errorMessage = e.message ?? 'Authentication failed.';
      } else {
        errorMessage = errorMessage.replaceFirst('Exception: ', '');
      }
      ref.read(authErrorProvider.notifier).state = errorMessage;
    } finally {
      ref.read(authLoadingProvider.notifier).state = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authLoadingProvider);
    final error = ref.watch(authErrorProvider);

    return GradientScaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Header
                    Icon(
                      Icons.wifi_rounded,
                      color: AppColors.accent.withOpacity(0.6),
                      size: 52,
                    ),
                    const SizedBox(height: 20),
                    Text('Welcome Back', style: AppTextStyles.heading1),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in to continue',
                      style: AppTextStyles.caption.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 40),

                    // Form Panel
                    GlassPanel(
                      padding: const EdgeInsets.all(24),
                      borderRadius: 24,
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Username', style: AppTextStyles.label),
                            const SizedBox(height: 8),
                            GlassTextField(
                              controller: _usernameController,
                              hintText: 'Enter your username',
                              prefixIcon: Icon(
                                Icons.person_outline_rounded,
                                color: AppColors.textSecondary,
                                size: 20,
                              ),
                              validator: (val) =>
                                  val == null || val.trim().isEmpty
                                      ? 'Username is required'
                                      : null,
                            ),
                            const SizedBox(height: 22),

                            Text('Password', style: AppTextStyles.label),
                            const SizedBox(height: 8),
                            GlassTextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              hintText: '••••••••',
                              prefixIcon: Icon(
                                Icons.lock_outline_rounded,
                                color: AppColors.textSecondary,
                                size: 20,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  color: AppColors.textSecondary,
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword),
                              ),
                              validator: (val) => val == null || val.isEmpty
                                  ? 'Password is required'
                                  : null,
                            ),
                            const SizedBox(height: 28),

                            // Error
                            if (error != null) ...[
                              GlassPanel(
                                borderRadius: 12,
                                padding: const EdgeInsets.all(12),
                                tint: AppColors.danger.withOpacity(0.1),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline_rounded,
                                        color: AppColors.danger, size: 18),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        error,
                                        style: AppTextStyles.caption.copyWith(
                                            color: AppColors.danger),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],

                            // Sign In Button
                            SizedBox(
                              width: double.infinity,
                              child: GlassButton(
                                label: 'Sign In',
                                onTap: isLoading ? null : _submit,
                                filled: true,
                                isLoading: isLoading,
                                borderRadius: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
