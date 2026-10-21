import 'package:flutter/material.dart';

import '../data/indian_states.dart';
import '../services/api_client.dart';
import '../state/auth_repository.dart';
import '../state/auth_scope.dart';
import '../widgets/auth_form_controls.dart';

const Color _navy = Color(0xFF102A43);
const Color _muted = Color(0xFF627D98);

/// Citizen registration.
///
/// Creates a **CITIZEN** account only: the backend hardcodes that role for
/// public registration and this screen deliberately offers no role selector.
/// `state` and `district` are plain strings on the server, so the state comes
/// from a bundled list and the district is typed by the citizen — no backend
/// lookup endpoint is invented for either.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.auth});

  /// Injectable for widget tests; the app reads it from [AuthScope].
  final AuthRepository? auth;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _districtController = TextEditingController();

  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  final _stateFocus = FocusNode();
  final _districtFocus = FocusNode();

  String? _state;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  bool _isSubmitting = false;
  String? _error;

  /// Field-level messages returned by the backend; cleared as the citizen
  /// edits the affected field.
  Map<String, String> _serverFieldErrors = const <String, String>{};

  AuthRepository? _auth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _auth ??= widget.auth ?? AuthScope.read(context);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _districtController.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    _stateFocus.dispose();
    _districtFocus.dispose();
    super.dispose();
  }

  void _clearServerError(String field) {
    if (!_serverFieldErrors.containsKey(field)) return;
    setState(() {
      _serverFieldErrors = Map<String, String>.from(_serverFieldErrors)
        ..remove(field);
    });
    // Re-run validation after the map has changed so the backend message does
    // not linger for an extra keystroke under `onUserInteraction`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _formKey.currentState?.validate();
    });
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate() || _isSubmitting) return;

    final auth = _auth!;
    FocusScope.of(context).unfocus();

    setState(() {
      _isSubmitting = true;
      _error = null;
      _serverFieldErrors = const <String, String>{};
    });

    try {
      await auth.register(
        name: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
        state: _state!,
        district: _districtController.text,
      );
    } on ApiException catch (exception) {
      if (!mounted) return;
      setState(() {
        _error = exception.message;
        _serverFieldErrors = exception.fieldErrors;
      });
      if (exception.fieldErrors.isNotEmpty) {
        _formKey.currentState?.validate();
      }
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Something went wrong. Please try again.');
      return;
    } finally {
      // A failed attempt must re-enable the form; on success the AuthGate
      // swaps this route out, so the spinner stays up instead of flashing.
      final registered = auth.status == AuthStatus.authenticated;
      if (mounted && !registered) {
        setState(() => _isSubmitting = false);
      }
    }

    // Registration succeeded: drop the pushed registration route so the
    // AuthGate underneath shows the existing HomeScreen instead of the login
    // form. Never pops further than the first route.
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  String? _validateName(String? value) {
    final server = _serverFieldErrors['name'];
    if (server != null) return server;
    if ((value ?? '').trim().isEmpty) return 'Enter your full name.';
    return null;
  }

  String? _validateEmail(String? value) {
    final server = _serverFieldErrors['email'];
    if (server != null) return server;
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Enter your email address.';
    if (!_emailPattern.hasMatch(email)) return 'Enter a valid email address.';
    return null;
  }

  String? _validatePassword(String? value) {
    final server = _serverFieldErrors['password'];
    if (server != null) return server;
    final password = value ?? '';
    if (password.isEmpty) return 'Create a password.';
    if (password.length < 8) return 'Use at least 8 characters.';
    return null;
  }

  String? _validateConfirm(String? value) {
    if (value != _passwordController.text) {
      return 'Passwords do not match.';
    }
    return null;
  }

  String? _validateState(String? value) {
    final server = _serverFieldErrors['state'];
    if (server != null) return server;
    if (value == null || value.isEmpty) return 'Select your state.';
    return null;
  }

  String? _validateDistrict(String? value) {
    final server = _serverFieldErrors['district'];
    if (server != null) return server;
    if ((value ?? '').trim().isEmpty) return 'Enter your district.';
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
                    Row(
                      children: [
                        IconButton(
                          onPressed: _isSubmitting
                              ? null
                              : () => Navigator.of(context).maybePop(),
                          tooltip: 'Back to sign in',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: _navy,
                            side: const BorderSide(color: Color(0xFFE4EAF0)),
                          ),
                          icon: const Icon(Icons.arrow_back_rounded, size: 20),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(child: AuthBrandHeader()),
                      ],
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      'Create your account',
                      style: TextStyle(
                        color: _navy,
                        fontSize: 26,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Reports you save are tied to your state and district so '
                      'the right community can see them.',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 14,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 26),
                    TextFormField(
                      controller: _nameController,
                      focusNode: _nameFocus,
                      enabled: !_isSubmitting,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      textCapitalization: TextCapitalization.words,
                      decoration: authInputDecoration(
                        label: 'Full name',
                        prefixIcon: Icons.person_outline_rounded,
                      ),
                      validator: _validateName,
                      onChanged: (_) => _clearServerError('name'),
                      onFieldSubmitted: (_) => _emailFocus.requestFocus(),
                    ),
                    const SizedBox(height: 16),
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
                      onChanged: (_) => _clearServerError('email'),
                      onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      focusNode: _passwordFocus,
                      enabled: !_isSubmitting,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: authInputDecoration(
                        label: 'Password',
                        helperText: 'At least 8 characters.',
                        prefixIcon: Icons.lock_outline_rounded,
                        suffixIcon: _visibilityToggle(
                          visible: !_obscurePassword,
                          enabled: !_isSubmitting,
                          onToggle: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      validator: _validatePassword,
                      onChanged: (_) => _clearServerError('password'),
                      onFieldSubmitted: (_) => _confirmFocus.requestFocus(),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmController,
                      focusNode: _confirmFocus,
                      enabled: !_isSubmitting,
                      obscureText: _obscureConfirmation,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: authInputDecoration(
                        label: 'Confirm password',
                        prefixIcon: Icons.lock_reset_rounded,
                        suffixIcon: _visibilityToggle(
                          visible: !_obscureConfirmation,
                          enabled: !_isSubmitting,
                          onToggle: () => setState(
                            () => _obscureConfirmation = !_obscureConfirmation,
                          ),
                        ),
                      ),
                      validator: _validateConfirm,
                      onFieldSubmitted: (_) => _stateFocus.requestFocus(),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      focusNode: _stateFocus,
                      initialValue: _state,
                      // Without this the button sizes itself to the widest
                      // entry ("Dadra and Nagar Haveli and Daman and Diu") and
                      // overflows the form on a narrow screen.
                      isExpanded: true,
                      items: [
                        for (final state in indianStatesAndUnionTerritories)
                          DropdownMenuItem<String>(
                            value: state,
                            child: Text(
                              state,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _navy,
                                fontSize: 14,
                              ),
                            ),
                          ),
                      ],
                      onChanged: _isSubmitting
                          ? null
                          : (value) {
                              setState(() => _state = value);
                              _clearServerError('state');
                            },
                      validator: _validateState,
                      decoration: authInputDecoration(
                        label: 'State',
                        prefixIcon: Icons.map_outlined,
                      ),
                      dropdownColor: Colors.white,
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: _muted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _districtController,
                      focusNode: _districtFocus,
                      enabled: !_isSubmitting,
                      textInputAction: TextInputAction.done,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.addressCity],
                      decoration: authInputDecoration(
                        label: 'District',
                        helperText: 'For example: Aizawl',
                        prefixIcon: Icons.location_on_outlined,
                      ),
                      validator: _validateDistrict,
                      onChanged: (_) => _clearServerError('district'),
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 18),
                      AuthErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 22),
                    AuthPrimaryButton(
                      label: 'Create account',
                      isBusy: _isSubmitting,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            'Already have an account?',
                            style: TextStyle(color: _muted, fontSize: 13.5),
                          ),
                          TextButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => Navigator.of(context).maybePop(),
                            style: TextButton.styleFrom(
                              foregroundColor: _navy,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                            child: const Text('Sign in'),
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

  Widget _visibilityToggle({
    required bool visible,
    required bool enabled,
    required VoidCallback onToggle,
  }) {
    return IconButton(
      tooltip: visible ? 'Hide password' : 'Show password',
      onPressed: enabled ? onToggle : null,
      icon: Icon(
        visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        size: 20,
        color: _muted,
      ),
    );
  }
}
