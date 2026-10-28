/// Core data model for a civic issue report.
///
/// This model is deliberately free of Flutter and platform dependencies so
/// that it can be serialised, unit tested and reused across the app.
library;

/// Lifecycle status of a civic report.
///
/// The status is stored using [Enum.name] so that renaming the human readable
/// [label] never breaks persisted data.
enum ReportStatus {
  reported('Reported'),
  underReview('Under Review'),
  accepted('Accepted'),
  inProgress('In Progress'),
  resolved('Resolved'),
  needsMoreInformation('Needs More Information');

  const ReportStatus(this.label);

  /// Human readable label shown in the UI.
  final String label;

  /// The linear sequence used for the progress indicator.
  ///
  /// [needsMoreInformation] is intentionally excluded because it is a side
  /// branch rather than a step in the pipeline.
  static const List<ReportStatus> pipeline = [
    ReportStatus.reported,
    ReportStatus.underReview,
    ReportStatus.accepted,
    ReportStatus.inProgress,
    ReportStatus.resolved,
  ];

  /// Resolves a persisted value back to a status.
  ///
  /// Unknown or missing values fall back to [ReportStatus.reported] instead of
  /// throwing, so that a single unexpected value can never break a whole file.
  static ReportStatus fromName(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      for (final status in ReportStatus.values) {
        if (status.name == trimmed || status.label == trimmed) {
          return status;
        }
      }
    }
    return ReportStatus.reported;
  }
}

/// Where the authoritative record for a report lives.
///
/// This is deliberately separate from [CivicReport.isSample]: a sampled report
/// is bundled demonstration data, whereas a server-backed report was accepted
/// by the municipal backend (and, when it was created on this device, is also
/// cached locally).
enum ReportOrigin {
  /// Created and stored only on this device. The backend has never seen it.
  local,

  /// Accepted by the municipal backend. The Prisma identifier is kept in
  /// [CivicReport.serverId]; a local copy may still exist.
  server,
}

/// A single entry in a report's status history.
class StatusEvent {
  const StatusEvent({required this.status, required this.timestamp, this.note});

  final ReportStatus status;
  final DateTime timestamp;
  final String? note;

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'timestamp': timestamp.toIso8601String(),
    if (note != null && note!.trim().isNotEmpty) 'note': note,
  };

  factory StatusEvent.fromJson(Map<String, dynamic> json) {
    return StatusEvent(
      status: ReportStatus.fromName(json['status']),
      timestamp: _parseDate(json['timestamp']) ?? DateTime.now(),
      note: _asNullableString(json['note']),
    );
  }
}

/// A citizen-submitted civic issue report.
class CivicReport {
  const CivicReport({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.locationLabel,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.landmark,
    this.status = ReportStatus.reported,
    this.photoFileName,
    this.adminNotes,
    this.statusHistory = const <StatusEvent>[],
    this.isSample = false,
    this.origin = ReportOrigin.local,
    this.serverId,
    this.serverPhotoPath,
    this.state,
    this.district,
  });

  /// Unique, locally generated identifier.
  final String id;
  final String category;
  final String title;
  final String description;

  /// Name of the image file stored by [ReportStore], or null when no photo
  /// was attached (for example, demonstration data).
  final String? photoFileName;

  /// Human readable location name chosen by the citizen: a place or address
  /// such as "Kulikawn, Aizawl". Never interchangeable with [landmark].
  final String locationLabel;

  /// Optional extra directions such as "Near the community hall".
  ///
  /// Null for reports saved before the field existed and whenever the
  /// citizen left it blank.
  final String? landmark;

  final double latitude;
  final double longitude;

  final DateTime createdAt;
  final ReportStatus status;

  /// Optional notes written by the local demonstration administration mode.
  final String? adminNotes;

  /// Chronological history of status changes.
  final List<StatusEvent> statusHistory;

  /// True for bundled demonstration data that is never persisted.
  final bool isSample;

  /// Whether this record is local-only or was accepted by the backend.
  final ReportOrigin origin;

  /// The backend's Prisma identifier once the report has been submitted, or
  /// null while the report is still local-only.
  final String? serverId;

  /// The backend's own photo reference (`photoPath`), kept strictly separate
  /// from [photoFileName]. It is set only once the backend confirms the upload,
  /// so a local photo and a server photo are never confused.
  final String? serverPhotoPath;

  /// Whether the backend has accepted this report.
  bool get isServerBacked => origin == ReportOrigin.server;

  /// Whether the backend holds an image for this report.
  bool get hasServerPhoto =>
      isServerBacked && serverPhotoPath != null && serverPhotoPath!.isNotEmpty;

  /// Whether a photo reference exists. The file itself may be missing on disk.
  bool get hasPhoto => photoFileName != null && photoFileName!.isNotEmpty;

  /// The state this report belongs to, as recorded by the backend.
  final String? state;

  /// The district this report belongs to, as recorded by the backend.
  final String? district;

  /// Whether this report stores a usable reporting point.
  ///
  /// Older entries parsed without coordinates fall back to 0, 0, and a point
  /// at Null Island is never a real selection, so both are reported as
  /// missing instead of being rendered as an address.
  bool get hasCoordinates {
    if (latitude.isNaN || longitude.isNaN) return false;
    if (!latitude.isFinite || !longitude.isFinite) return false;
    if (latitude.abs() > 90 || longitude.abs() > 180) return false;
    return !(latitude == 0 && longitude == 0);
  }

  /// The landmark trimmed to a plain value, or null when it holds nothing.
  String? get landmarkOrNull {
    final value = landmark?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  CivicReport copyWith({
    String? id,
    String? category,
    String? title,
    String? description,
    String? photoFileName,
    bool clearPhoto = false,
    String? locationLabel,
    String? landmark,
    bool clearLandmark = false,
    double? latitude,
    double? longitude,
    DateTime? createdAt,
    ReportStatus? status,
    String? adminNotes,
    bool clearAdminNotes = false,
    List<StatusEvent>? statusHistory,
    bool? isSample,
    ReportOrigin? origin,
    String? serverId,
    String? serverPhotoPath,
    String? state,
    String? district,
  }) {
    return CivicReport(
      id: id ?? this.id,
      category: category ?? this.category,
      title: title ?? this.title,
      description: description ?? this.description,
      photoFileName: clearPhoto ? null : (photoFileName ?? this.photoFileName),
      locationLabel: locationLabel ?? this.locationLabel,
      landmark: clearLandmark ? null : (landmark ?? this.landmark),
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      adminNotes: clearAdminNotes ? null : (adminNotes ?? this.adminNotes),
      statusHistory: statusHistory ?? this.statusHistory,
      isSample: isSample ?? this.isSample,
      origin: origin ?? this.origin,
      serverId: serverId ?? this.serverId,
      serverPhotoPath: serverPhotoPath ?? this.serverPhotoPath,
      state: state ?? this.state,
      district: district ?? this.district,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'title': title,
    'description': description,
    'photoFileName': photoFileName,
    'locationLabel': locationLabel,
    'landmark': landmarkOrNull,
    'latitude': latitude,
    'longitude': longitude,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'adminNotes': adminNotes,
    'statusHistory': statusHistory.map((event) => event.toJson()).toList(),
    'isSample': isSample,
    'origin': origin.name,
    'serverId': serverId,
    'serverPhotoPath': serverPhotoPath,
    if (state != null) 'state': state,
    if (district != null) 'district': district,
  };

  /// Rebuilds a report from persisted JSON.
  ///
  /// Only [id] is strictly required. Every other value is normalised so that a
  /// partially corrupt entry can still be recovered. Throws [FormatException]
  /// when the identifier is missing, allowing the store to preserve the raw
  /// file rather than dropping data silently.
  factory CivicReport.fromJson(Map<String, dynamic> json) {
    final id = _asNullableString(json['id']);
    if (id == null || id.isEmpty) {
      throw const FormatException('Report entry is missing its identifier.');
    }

    final rawHistory = json['statusHistory'];
    final history = <StatusEvent>[];
    if (rawHistory is List) {
      for (final entry in rawHistory) {
        if (entry is Map) {
          history.add(StatusEvent.fromJson(Map<String, dynamic>.from(entry)));
        }
      }
    }

    final createdAt = _parseDate(json['createdAt']) ?? DateTime.now();

    // Keep history chronologically ordered even if the file was edited.
    history.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return CivicReport(
      id: id,
      category: _asString(json['category'], fallback: 'Other'),
      title: _asString(json['title'], fallback: 'Untitled report'),
      description: _asString(json['description']),
      photoFileName: _asNullableString(json['photoFileName']),
      locationLabel: _asString(
        json['locationLabel'],
        fallback: 'Location unavailable',
      ),
      // Older reports simply have no landmark key; they stay null.
      landmark: _asNullableString(json['landmark']),
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
      createdAt: createdAt,
      status: ReportStatus.fromName(json['status']),
      adminNotes: _asNullableString(json['adminNotes']),
      statusHistory: history,
      isSample: json['isSample'] == true,
      origin: _originFromName(json['origin']),
      serverId: _asNullableString(json['serverId']),
      serverPhotoPath: _asNullableString(json['serverPhotoPath']),
      state: _asNullableString(json['state']),
      district: _asNullableString(json['district']),
    );
  }
}

String _asString(Object? value, {String fallback = ''}) {
  if (value is String && value.trim().isNotEmpty) return value;
  if (value != null) {
    final text = value.toString();
    if (text.trim().isNotEmpty) return text;
  }
  return fallback;
}

String? _asNullableString(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value;
  return null;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}

DateTime? _parseDate(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

ReportOrigin _originFromName(Object? value) {
  if (value is String) {
    for (final origin in ReportOrigin.values) {
      if (origin.name == value.trim()) return origin;
    }
  }
  return ReportOrigin.local;
}
