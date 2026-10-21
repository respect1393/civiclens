import 'package:flutter/material.dart';

import '../services/location_service.dart';

const Color _navy = Color(0xFF102A43);
const Color _teal = Color(0xFF13B8A6);

/// What the citizen chose to do with a device fix that could not be verified
/// as precise.
///
/// Reaching this dialog always means the fix was shown and explained first;
/// nothing is ever applied without an explicit choice.
enum LocationFixChoice { useIt, retry, chooseOnMap }

/// Explains how accurate [position] really is and asks what to do with it.
///
/// Returns null when the dialog was dismissed without a decision, which
/// callers must treat exactly like "choose on map": the existing selection
/// stays untouched.
///
/// [chooseOnMapLabel] is the wording of the manual-selection action, which
/// differs between the map picker (the map is right there) and the report
/// form (it opens the map picker).
Future<LocationFixChoice?> showLocationAccuracyDialog(
  BuildContext context, {
  required DeviceLocation position,
  required List<LocationIssue> issues,
  String chooseOnMapLabel = 'Choose on map',
}) {
  return showDialog<LocationFixChoice>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => LocationAccuracyDialog(
      position: position,
      issues: issues,
      chooseOnMapLabel: chooseOnMapLabel,
      onDismissed: (choice) => Navigator.of(dialogContext).pop(choice),
    ),
  );
}

/// The accuracy dialog itself, wired up by [showLocationAccuracyDialog].
class LocationAccuracyDialog extends StatelessWidget {
  const LocationAccuracyDialog({
    super.key,
    required this.position,
    required this.issues,
    required this.chooseOnMapLabel,
    required this.onDismissed,
  });

  final DeviceLocation position;
  final List<LocationIssue> issues;
  final String chooseOnMapLabel;
  final ValueChanged<LocationFixChoice> onDismissed;

  @override
  Widget build(BuildContext context) {
    final accuracy = position.accuracy;
    final accuracyLine = accuracy == null || !accuracy.isFinite
        ? 'Your device did not report an accuracy for this position.'
        : 'Reported accuracy: about ±${formatMetres(accuracy)}.';

    final reasons = explainLocationIssues(issues);

    return AlertDialog(
      title: const Text('Location may be inaccurate'),
      content: Text(
        [
          if (reasons.isNotEmpty) reasons,
          accuracyLine,
          'Try again for a better fix, use this position as it is, or choose '
              'the point manually instead.',
        ].join(' '),
      ),
      actions: [
        TextButton(
          onPressed: () => onDismissed(LocationFixChoice.chooseOnMap),
          child: Text(chooseOnMapLabel),
        ),
        TextButton(
          onPressed: () => onDismissed(LocationFixChoice.retry),
          child: const Text('Try again'),
        ),
        FilledButton(
          onPressed: () => onDismissed(LocationFixChoice.useIt),
          style: FilledButton.styleFrom(
            backgroundColor: _teal,
            foregroundColor: _navy,
          ),
          child: const Text('Use this location'),
        ),
      ],
    );
  }
}
