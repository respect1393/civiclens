/// Shared building blocks for the login and registration screens, so both
/// forms stay visually identical without copying their markup.
library;

import 'package:flutter/material.dart';

const Color _navy = Color(0xFF102A43);
const Color _teal = Color(0xFF13B8A6);
const Color _muted = Color(0xFF627D98);
const Color _border = Color(0xFFE4EAF0);
const Color _errorFill = Color(0xFFFDECEC);
const Color _errorText = Color(0xFFB3261E);

/// The CIVICLENS wordmark shown at the top of the auth screens.
class AuthBrandHeader extends StatelessWidget {
  const AuthBrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 46,
          width: 46,
          decoration: BoxDecoration(
            color: _navy,
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(
            Icons.location_city_rounded,
            color: _teal,
            size: 27,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CIVICLENS',
                style: TextStyle(
                  color: _navy,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'YOUR CITY. YOUR VOICE.',
                style: TextStyle(
                  color: _muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Consistent text-field styling for every auth input.
InputDecoration authInputDecoration({
  required String label,
  IconData? prefixIcon,
  Widget? suffixIcon,
  String? helperText,
}) {
  const radius = BorderRadius.all(Radius.circular(14));
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: _muted, fontSize: 14),
    helperText: helperText,
    helperStyle: const TextStyle(color: _muted, fontSize: 11),
    prefixIcon: prefixIcon == null
        ? null
        : Icon(prefixIcon, size: 20, color: _muted),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: _border),
    ),
    enabledBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: _border),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: _teal, width: 1.6),
    ),
    errorBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: _errorText),
    ),
    focusedErrorBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: _errorText, width: 1.6),
    ),
  );
}

/// Full-width primary action that swaps its label for a spinner while busy.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.isBusy,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: isBusy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _teal,
          foregroundColor: _navy,
          disabledBackgroundColor: _teal.withValues(alpha: 0.45),
          disabledForegroundColor: _navy.withValues(alpha: 0.55),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isBusy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: _navy,
                ),
              )
            : Text(label),
      ),
    );
  }
}

/// Inline, citizen-safe error banner. Never renders raw server payloads.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _errorFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _errorText.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: _errorText, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: _errorText,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
