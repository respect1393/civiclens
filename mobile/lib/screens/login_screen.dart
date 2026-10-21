import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../state/auth_repository.dart';
import '../state/auth_scope.dart';
import '../widgets/auth_form_controls.dart';
import 'register_screen.dart';

const Color _navy = Color(0xFF102A43);
const Color _muted = Color(0xFF627D98);

/// Citizen sign-in.
///
/// Flow: validate → `POST /api/auth/login` → store the JWT securely → the
/// surrounding [AuthGate] swaps this screen for the existing `HomeScreen`.
/// There is no local or mocked sign-in: the backend is the only authority.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.auth});

  /// Injectable for widget tests; the app reads it from [AuthScope].
  final AuthRepository? auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _error;

  AuthRepository? _auth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _auth ??= widget.auth ?? AuthScope.read(context);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate() || _isSubmitting) return;

    final auth = _auth!;
    FocusScope.of(context).unfocus();

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await auth.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } on ApiException catch (exception) {
      if (!mounted) return;
      setState(() => _error = exception.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      // On success the AuthGate swaps this screen out, so the spinner stays
      // up instead of flashing an enabled button for one frame.
      final signedIn = auth.status == AuthStatus.authenticated;
      if (mounted && !signedIn) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _openRegistration() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const RegisterScreen()));
  }

  String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Enter your email address.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if ((value ?? '').isEmpty) return 'Enter your password.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AuthBrandHeader(),
                    const SizedBox(height: 34),
                    const Text(
                      'Welcome back',
                      style: TextStyle(
                        color: _navy,
                        fontSize: 27,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sign in to report civic issues and track what '
                      'happens next.',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 14,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _emailController,
                      focusNode: _emailFocus,
                      enabled: !_isSubmitting,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: authInputDecoration(
                        label: 'Email address',
                        prefixIcon: Icons.mail_outline_rounded,
                      ),
                      validator: _validateEmail,
                      onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      focusNode: _passwordFocus,
                      enabled: !_isSubmitting,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      decoration: authInputDecoration(
                        label: 'Password',
                        prefixIcon: Icons.lock_outline_rounded,
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: _isSubmitting
                              ? null
                              : () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                            color: _muted,
                          ),
                        ),
                      ),
                      validator: _validatePassword,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 18),
                      AuthErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 22),
                    AuthPrimaryButton(
                      label: 'Sign in',
                      isBusy: _isSubmitting,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            'New to CIVICLENS?',
                            style: TextStyle(color: _muted, fontSize: 13.5),
                          ),
                          TextButton(
                            onPressed: _isSubmitting ? null : _openRegistration,
                            style: TextButton.styleFrom(
                              foregroundColor: _navy,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                            child: const Text('Create an account'),
                          ),
                        ],
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
