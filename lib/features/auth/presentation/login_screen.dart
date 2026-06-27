import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _awaitingEmailConfirmation = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.isLoading;

    ref.listen(authStateProvider, (_, next) {
      if (next.valueOrNull != null) context.go('/map');
    });

    ref.listen(authNotifierProvider, (prev, next) {
      if (prev?.isLoading == true && next.isLoading == false && !next.hasError) {
        // Signup completed but no session yet → email confirmation required
        if (_isSignUp && Supabase.instance.client.auth.currentSession == null) {
          setState(() => _awaitingEmailConfirmation = true);
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(_isSignUp ? 'Create Account' : 'Sign In'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.forestGreen,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 16),

          // OAuth buttons
          OutlinedButton.icon(
            onPressed: isLoading ? null : () => ref.read(authNotifierProvider.notifier).signInWithGoogle(),
            icon: const Icon(Icons.g_mobiledata, size: 24),
            label: const Text('Continue with Google'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: isLoading ? null : () => ref.read(authNotifierProvider.notifier).signInWithApple(),
            icon: const Icon(Icons.apple, size: 24),
            label: const Text('Continue with Apple'),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Row(children: [
              Expanded(child: Divider()),
              Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('or')),
              Expanded(child: Divider()),
            ]),
          ),

          // Email / password
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),

          FilledButton(
            onPressed: isLoading ? null : _submit,
            child: isLoading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator.adaptive(strokeWidth: 2))
                : Text(_isSignUp ? 'Create Account' : 'Sign In'),
          ),

          const SizedBox(height: 16),
          TextButton(
            onPressed: () => setState(() => _isSignUp = !_isSignUp),
            child: Text(_isSignUp ? 'Already have an account? Sign in' : "Don't have an account? Create one"),
          ),

          if (_awaitingEmailConfirmation)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.mark_email_unread_outlined, color: Colors.green.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Revisa tu email y confirma tu cuenta para continuar.',
                      style: TextStyle(color: Colors.green.shade800),
                    ),
                  ),
                ],
              ),
            )
          else if (authState.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(authState.error.toString(), style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final email    = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;

    final notifier = ref.read(authNotifierProvider.notifier);
    if (_isSignUp) {
      await notifier.signUp(email, password);
    } else {
      await notifier.signInWithEmail(email, password);
    }
  }
}
