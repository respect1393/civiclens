import 'package:flutter/material.dart';

import '../models/civic_report.dart';

/// Maps a report category to a representative icon.
IconData categoryIcon(String category) {
  final value = category.toLowerCase();
  if (value.contains('pothole') || value.contains('road')) {
    return Icons.add_road_rounded;
  }
  if (value.contains('streetlight') || value.contains('light')) {
    return Icons.lightbulb_outline_rounded;
  }
  if (value.contains('water')) {
    return Icons.water_drop_outlined;
  }
  if (value.contains('garbage') || value.contains('waste')) {
    return Icons.delete_outline_rounded;
  }
  if (value.contains('drain')) {
    return Icons.water_rounded;
  }
  return Icons.report_problem_outlined;
}

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats a timestamp as `12 Oct 2026, 14:05` without extra dependencies.
String formatDateTime(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = _months[local.month - 1];
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day $month ${local.year}, $hour:$minute';
}

/// Formats a timestamp as a short date.
String formatDate(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = _months[local.month - 1];
  return '$day $month ${local.year}';
}

final RegExp _coordinatePattern = RegExp(
  r'^-?\d{1,3}\.\d+\s*,\s*-?\d{1,3}\.\d+$',
);

/// True when [value] is a bare `latitude, longitude` pair.
///
/// Older builds stored the raw coordinates as the location label when no
/// address could be resolved. Those values are coordinates, not a place name.
bool looksLikeCoordinates(String value) {
  return _coordinatePattern.hasMatch(value.trim());
}

/// The human readable location name to display.
///
/// Never returns raw coordinates: a report without a usable name says so
/// instead of presenting numbers as an address.
String displayLocationName(CivicReport report) {
  final label = report.locationLabel.trim();

  if (label.isEmpty || label.toLowerCase() == 'location unavailable') {
    return 'Location name not available';
  }
  if (looksLikeCoordinates(label)) {
    return 'Location name not available';
  }
  return label;
}

/// The stored point rendered for display, or null when the report has none.
String? displayCoordinates(CivicReport report) {
  if (!report.hasCoordinates) return null;
  return '${report.latitude.toStringAsFixed(6)}, '
      '${report.longitude.toStringAsFixed(6)}';
}
