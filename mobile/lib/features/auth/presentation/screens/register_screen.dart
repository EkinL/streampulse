import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme.dart';
import '../../domain/auth_state.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_form_field.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/utils/extensions.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedTerms = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleRegister() {
    if (_formKey.currentState?.validate() ?? false) {
      ref.read(authProvider.notifier).register(
            username: _usernameController.text.trim(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
            acceptedTerms: _acceptedTerms,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next is AuthAuthenticated) {
        context.go('/streams');
      } else if (next is AuthError) {
        context.showSnackBar(next.message, isError: true);
      }
    });

    final isLoading = authState is AuthLoading;

    return Scaffold(
      backgroundColor: context.colors.bg,
      body: Stack(
        children: [
          // Top-right purple glow
          Positioned(
            top: -80,
            right: -80,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    context.colors.accent.withValues(alpha: 0.18),
                    context.colors.accent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // Bottom-left red glow
          Positioned(
            bottom: -100,
            left: -100,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFF6B6B).withValues(alpha: 0.12),
                    const Color(0xFFFF6B6B).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // Main content
          SafeArea(
            child: Column(
              children: [
                // Back button
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, top: 8),
                    child: IconButton(
                      icon: Icon(
                        Icons.arrow_back,
                        color: context.colors.text1,
                      ),
                      tooltip: 'Retour',
                      onPressed: () => context.go('/login'),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          // Heading
                          Text(
                            'Create Account',
                            style: GoogleFonts.inter(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: context.colors.text1,
                              letterSpacing: -1.8,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Join the StreamPulse community',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: context.colors.text2,
                              letterSpacing: 0.35,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 40),
                          // Username
                          _buildLabel('USERNAME'),
                          const SizedBox(height: 8),
                          AuthFormField(
                            controller: _usernameController,
                            label: 'Username',
                            hintText: 'Choose a username',
                            prefixIcon: const Icon(Icons.person_outlined),
                            validator: Validators.username,
                          ),
                          const SizedBox(height: 24),
                          // Email
                          _buildLabel('EMAIL ADDRESS'),
                          const SizedBox(height: 8),
                          AuthFormField(
                            controller: _emailController,
                            label: 'Email',
                            hintText: 'name@example.com',
                            keyboardType: TextInputType.emailAddress,
                            prefixIcon: const Icon(Icons.email_outlined),
                            validator: Validators.email,
                          ),
                          const SizedBox(height: 24),
                          // Password
                          _buildLabel('PASSWORD'),
                          const SizedBox(height: 8),
                          AuthFormField(
                            controller: _passwordController,
                            label: 'Password',
                            hintText: 'Create a password',
                            obscureText: _obscurePassword,
                            prefixIcon: const Icon(Icons.lock_outlined),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              tooltip: _obscurePassword
                                  ? 'Afficher le mot de passe'
                                  : 'Masquer le mot de passe',
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            validator: Validators.password,
                          ),
                          const SizedBox(height: 24),
                          // Confirm Password
                          _buildLabel('CONFIRM PASSWORD'),
                          const SizedBox(height: 8),
                          AuthFormField(
                            controller: _confirmPasswordController,
                            label: 'Confirm Password',
                            hintText: 'Confirm your password',
                            obscureText: _obscureConfirmPassword,
                            prefixIcon: const Icon(Icons.lock_outlined),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              tooltip: _obscureConfirmPassword
                                  ? 'Afficher le mot de passe'
                                  : 'Masquer le mot de passe',
                              onPressed: () {
                                setState(() {
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword;
                                });
                              },
                            ),
                            validator: (value) => Validators.confirmPassword(
                              value,
                              _passwordController.text,
                            ),
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _handleRegister(),
                          ),
                          const SizedBox(height: 32),
                          // Create Account button
                          SizedBox(
                            height: 56,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment(-0.3, -1),
                                  end: Alignment(0.3, 1),
                                  colors: [SP.gradStart, SP.gradEnd],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: context.colors.accent.withValues(alpha: 0.10),
                                    offset: const Offset(0, 10),
                                    blurRadius: 15,
                                    spreadRadius: -3,
                                  ),
                                ],
                              ),
                              child: MaterialButton(
                                onPressed: isLoading ? null : _handleRegister,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: EdgeInsets.zero,
                                child: isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: SP.btnText,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Create Account',
                                            style: GoogleFonts.inter(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              color: SP.btnText,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Icon(
                                            Icons.chevron_right,
                                            color: SP.btnText,
                                            size: 22,
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Case a cocher obligatoire (recueil du
                          // consentement aux conditions d'utilisation, voir
                          // docs/rgpd.md) : integree au Form pour que
                          // _handleRegister la refuse comme n'importe quel
                          // autre champ invalide. Le traitement du compte
                          // lui-meme reste fonde sur l'execution du contrat,
                          // pas sur ce consentement ; la case sert de preuve
                          // que la personne a vu et accepte les conditions.
                          FormField<bool>(
                            initialValue: _acceptedTerms,
                            validator: (value) => (value ?? false)
                                ? null
                                : 'Vous devez accepter les conditions d\'utilisation',
                            builder: (field) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: Checkbox(
                                          value: _acceptedTerms,
                                          activeColor: context.colors.accent,
                                          side: BorderSide(color: context.colors.divider),
                                          onChanged: (checked) {
                                            setState(() {
                                              _acceptedTerms = checked ?? false;
                                            });
                                            field.didChange(_acceptedTerms);
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      // Pas de GestureDetector englobant : le
                                      // lien "politique de confidentialite"
                                      // porte deja son propre
                                      // TapGestureRecognizer, un tap-toggle
                                      // par-dessus entrerait en conflit avec
                                      // lui dans l'arene de gestes. Cocher se
                                      // fait via la case elle-meme.
                                      Expanded(
                                        child: RichText(
                                          text: TextSpan(
                                            text: 'J\'accepte les conditions d\'utilisation et la ',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: context.colors.text3,
                                            ),
                                            children: [
                                              TextSpan(
                                                text: 'politique de confidentialité',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: context.colors.accent,
                                                ),
                                                recognizer: TapGestureRecognizer()
                                                  ..onTap = () => context.push('/privacy'),
                                              ),
                                              TextSpan(
                                                text: '.',
                                                style: GoogleFonts.inter(fontSize: 12, color: context.colors.text3),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (field.hasError)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 34, top: 4),
                                      child: Text(
                                        field.errorText!,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: context.colors.error,
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          // Sign In footer
                          GestureDetector(
                            onTap:
                                isLoading ? null : () => context.go('/login'),
                            child: RichText(
                              textAlign: TextAlign.center,
                              text: TextSpan(
                                text: 'Already have an account? ',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: context.colors.text2,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'Sign In',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: context.colors.accent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: context.colors.text2,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
