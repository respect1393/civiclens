import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/civic_report.dart';
import '../state/report_scope.dart';
import '../utils/report_format.dart';

const Color _navy = Color(0xFF102A43);
const Color _muted = Color(0xFF627D98);
const Color _background = Color(0xFFF5F7FA);
const Color _border = Color(0xFFE4EAF0);

/// Thumbnail for a report's photo evidence.
///
/// Falls back to a category icon when no photo was attached, when the file is
/// missing from disk, or when the image cannot be decoded. This keeps stored
/// reports usable even if their photo file was removed.
class ReportThumbnail extends StatefulWidget {
  const ReportThumbnail({
    super.key,
    required this.report,
    this.size = 56,
    this.borderRadius = 14,
  });

  final CivicReport report;
  final double size;
  final double borderRadius;

  @override
  State<ReportThumbnail> createState() => _ReportThumbnailState();
}

class _ReportThumbnailState extends State<ReportThumbnail> {
  Future<Uint8List?>? _imageFuture;
  String? _imageFutureKey;

  /// Returns a stable Future for [report].
  ///
  /// The future is cached so its identity does not change on every rebuild.
  /// Passing a fresh Future into FutureBuilder each build makes it resubscribe
  /// and setState forever, which never settles.
  Future<Uint8List?> _resolveImage(BuildContext context) {
    final key =
        '${widget.report.id}|${widget.report.photoFileName}|'
        '${widget.report.serverPhotoPath}';
    if (_imageFuture == null || _imageFutureKey != key) {
      _imageFutureKey = key;
      _imageFuture = ReportScope.read(context)
          .resolveReportImage(widget.report);
    }
    return _imageFuture!;
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final hasImage = report.hasPhoto || report.hasServerPhoto;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: SizedBox(
        height: widget.size,
        width: widget.size,
        child: hasImage
            ? FutureBuilder<Uint8List?>(
                future: _resolveImage(context),
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (snapshot.connectionState != ConnectionState.done ||
                      bytes == null) {
                    return _fallback(report);
                  }
                  return Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _fallback(report),
                  );
                },
              )
            : _fallback(report),
      ),
    );
  }

  Widget _fallback(CivicReport report) {
    return Container(
      color: _background,
      alignment: Alignment.center,
      child: Icon(
        categoryIcon(report.category),
        color: _navy,
        size: widget.size * 0.5,
      ),
    );
  }
}

/// Larger, full-width photo panel used on the report details screen.
class ReportPhotoPanel extends StatefulWidget {
  const ReportPhotoPanel({super.key, required this.report});

  final CivicReport report;

  @override
  State<ReportPhotoPanel> createState() => _ReportPhotoPanelState();
}

class _ReportPhotoPanelState extends State<ReportPhotoPanel> {
  Future<Uint8List?>? _imageFuture;
  String? _imageFutureKey;

  Future<Uint8List?> _resolveImage(BuildContext context) {
    final key =
        '${widget.report.id}|${widget.report.photoFileName}|'
        '${widget.report.serverPhotoPath}';
    if (_imageFuture == null || _imageFutureKey != key) {
      _imageFutureKey = key;
      _imageFuture = ReportScope.read(context)
          .resolveReportImage(widget.report);
    }
    return _imageFuture!;
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    if (!report.hasPhoto && !report.hasServerPhoto) {
      return _placeholder(
        icon: categoryIcon(report.category),
        label: 'No photo was attached to this report.',
      );
    }

    return FutureBuilder<Uint8List?>(
      future: _resolveImage(context),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _placeholder(
            icon: Icons.image_outlined,
            label: 'Loading photo...',
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return _placeholder(
            icon: Icons.broken_image_outlined,
            label: 'This report\'s photo could not be loaded.',
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.memory(
            bytes,
            height: 240,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _placeholder(
              icon: Icons.broken_image_outlined,
              label: 'This photo could not be displayed.',
            ),
          ),
        );
      },
    );
  }

  Widget _placeholder({required IconData icon, required String label}) {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: _muted),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
