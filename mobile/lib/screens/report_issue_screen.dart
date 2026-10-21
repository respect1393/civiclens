import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;

import '../services/api_client.dart';
import '../services/location_service.dart';
import '../services/place_search_service.dart';
import '../state/report_scope.dart';
import '../widgets/location_accuracy_dialog.dart';
import '../widgets/report_saved_dialog.dart';
import 'location_picker_screen.dart';

const Color _navy = Color(0xFF102A43);
const Color _teal = Color(0xFF13B8A6);
const Color _muted = Color(0xFF627D98);
const Color _background = Color(0xFFF5F7FA);
const Color _border = Color(0xFFE4EAF0);

/// Shared shape for the location actions, sized for a comfortable thumb.
final ButtonStyle _outlinedButtonStyle = OutlinedButton.styleFrom(
  foregroundColor: _navy,
  padding: const EdgeInsets.symmetric(vertical: 15),
  side: const BorderSide(color: _border),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
);

class ReportIssueScreen extends StatefulWidget {
  const ReportIssueScreen({
    super.key,
    this.locationService,
    this.placeSearchService,
    this.imagePicker,
  });

  /// Injectable so widget tests can exercise permission and failure handling
  /// without a GPS radio or platform channels.
  final LocationService? locationService;

  /// Injectable so tests can supply address suggestions without touching the
  /// public Nominatim endpoint. Also handed to the map picker so the whole
  /// flow shares one implementation.
  final PlaceSearchService? placeSearchService;

  /// Injectable so widget tests can attach photo evidence without the
  /// platform image picker.
  final ImagePicker? imagePicker;

  @override
  State<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends State<ReportIssueScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  /// Focus is only ever requested explicitly (after a failed submit), never
  /// as a side effect of rebuilding, picking a photo or choosing a location.
  final _titleFocus = FocusNode();
  final _descriptionFocus = FocusNode();
  final _locationNameFocus = FocusNode();

  late final ImagePicker _picker = widget.imagePicker ?? ImagePicker();

  late final LocationService _locationService =
      widget.locationService ?? const GeolocatorLocationService();

  late final PlaceSearchService _placeSearchService;
  late final bool _ownsPlaceService;

  final List<String> _categories = [
    'Pothole / Road Damage',
    'Broken Streetlight',
    'Water Supply',
    'Garbage / Waste',
    'Drainage',
    'Other',
  ];

  String? _selectedCategory;
  XFile? _photo;
  Uint8List? _photoBytes;
  bool _isPickingPhoto = false;
  bool _isSubmitting = false;

  /// Human readable place name of the reporting point. Separate from the
  /// coordinates above and the optional landmark below.
  final _locationNameController = TextEditingController();

  /// Optional extra directions such as "Near the community hall".
  final _landmarkController = TextEditingController();

  /// True once the citizen typed in the location-name field themselves.
  ///
  /// A cleared field counts as "no manual name", so a later automatic
  /// suggestion can fill it again. This is the whole rule: automatic
  /// suggestions only ever write while this flag is false.
  bool _locationNameEdited = false;

  /// Inline error for the location-name field, raised only by an explicit
  /// submit so the field never turns red while the form is still being
  /// filled in.
  String? _locationNameError;

  /// Set when the reporting point changed while a landmark was written, so
  /// the citizen is asked to review it instead of losing it silently.
  bool _landmarkMayBeStale = false;

  /// The problem location chosen by the citizen (from the map picker or the
  /// "use my current location" shortcut). This is intentionally kept separate
  /// from [_devicePosition], which only reflects the device's GPS reading.
  double? _problemLatitude;
  double? _problemLongitude;

  /// Most recent device GPS reading, used only to centre the map and to show
  /// the current-location shortcut result.
  DeviceLocation? _devicePosition;
  bool _isGettingLocation = false;

  bool get _hasProblemLocation =>
      _problemLatitude != null && _problemLongitude != null;

  @override
  void initState() {
    super.initState();

    _ownsPlaceService = widget.placeSearchService == null;
    _placeSearchService =
        widget.placeSearchService ?? NominatimPlaceSearchService();
  }

  /// Opens the map picker at the current selection and applies whatever the
  /// citizen confirms.
  ///
  /// Cancelling returns null and leaves every field exactly as it was, so
  /// opening the map can never save, clear or reset the report form.
  Future<void> _openLocationPicker() async {
    _dismissKeyboard();

    final currentName = _locationNameController.text.trim();

    final result = await Navigator.of(context).push<LocationSelection>(
      MaterialPageRoute<LocationSelection>(
        builder: (_) => LocationPickerScreen(
          initialLatitude: _problemLatitude ?? _devicePosition?.latitude,
          initialLongitude: _problemLongitude ?? _devicePosition?.longitude,
          initialLabel: currentName.isEmpty ? null : currentName,
          locationService: widget.locationService,
          placeSearchService: widget.placeSearchService,
        ),
      ),
    );

    if (!mounted || result == null) return;

    _applySelectedPoint(
      latitude: result.latitude,
      longitude: result.longitude,
      suggestedName: result.label,
    );
  }

  /// Makes the given point the selected reporting point.
  ///
  /// [suggestedName] is what the geocoder proposed for that point. It only
  /// ever replaces the field while the citizen has not typed their own name.
  void _applySelectedPoint({
    required double latitude,
    required double longitude,
    required String suggestedName,
  }) {
    final suggestion = suggestedName.trim();
    final pointChanged =
        !_hasProblemLocation ||
        _problemLatitude != latitude ||
        _problemLongitude != longitude;
    final previousName = _locationNameController.text.trim();

    setState(() {
      _problemLatitude = latitude;
      _problemLongitude = longitude;

      if (!_locationNameEdited && (pointChanged || previousName.isEmpty)) {
        _locationNameController.text = suggestion;
      }

      if (pointChanged && _landmarkController.text.trim().isNotEmpty) {
        _landmarkMayBeStale = true;
      }
    });

    if (_locationNameEdited &&
        suggestion.isNotEmpty &&
        suggestion != previousName) {
      _offerSuggestedName(suggestion);
    }
  }

  /// Asks whether a newly suggested name should replace the manual one.
  ///
  /// The manual name stays in place until the citizen accepts, so a late
  /// geocoder answer can never silently destroy their wording.
  void _offerSuggestedName(String suggestion) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        content: Text(
          'Location changed. Your location name was kept. The map suggests '
          '"$suggestion".',
        ),
        action: SnackBarAction(
          label: 'Use suggestion',
          onPressed: () {
            if (!mounted) return;
            setState(() {
              _locationNameController.text = suggestion;
              _locationNameEdited = false;
              _locationNameError = null;
            });
          },
        ),
      ),
    );
  }

  /// Reads a fresh, high-accuracy fix and offers it as the reporting point.
  ///
  /// A fix that meets the accuracy target is applied straight away. A fix
  /// that does not is never applied silently: the citizen is told how
  /// accurate it really is and decides whether to use it, ask again, or pick
  /// the point on the map themselves. Every failure leaves the form intact.
  Future<void> _getCurrentLocation() async {
    if (_isGettingLocation) return;

    // Never keep a text field focused while the permission prompt is showing;
    // otherwise the keyboard is reopened when focus is restored.
    _dismissKeyboard();

    setState(() => _isGettingLocation = true);

    DeviceLocation? fix;
    Object? error;
    var approximateOnly = false;

    try {
      fix = await _locationService.getCurrentLocation();
      approximateOnly = await _locationService.isApproximateOnly();
    } on LocationServiceException catch (caught) {
      error = caught;
    } catch (caught) {
      error = caught;
    } finally {
      if (mounted) {
        setState(() => _isGettingLocation = false);
      }
    }

    if (!mounted) return;

    if (error != null) {
      _showMessage(
        error is LocationServiceException
            ? error.message
            : 'Could not read your location. You can still choose the '
                  'problem location manually on the map.',
        actionLabel: 'RETRY',
        onAction: () => _getCurrentLocation(),
      );
      return;
    }

    final position = fix;
    if (position == null) return;

    final issues = position.issues(approximatePermission: approximateOnly);

    if (issues.isEmpty) {
      await _applyDeviceFix(position);
      return;
    }

    final choice = await showLocationAccuracyDialog(
      context,
      position: position,
      issues: issues,
      chooseOnMapLabel: 'Choose on map',
    );

    if (!mounted || choice == null) return;

    switch (choice) {
      case LocationFixChoice.useIt:
        await _applyDeviceFix(position);
      case LocationFixChoice.retry:
        _getCurrentLocation();
      case LocationFixChoice.chooseOnMap:
        // Straight to manual selection: the map picker keeps every field
        // exactly as it is when it is cancelled.
        await _openLocationPicker();
    }
  }

  /// Stores [position] as the reporting point and looks up its name.
  Future<void> _applyDeviceFix(DeviceLocation position) async {
    if (!mounted) return;

    _devicePosition = position;

    // Coordinates first: they are usable even if no address can be found.
    _applySelectedPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      suggestedName: '',
    );

    if (_locationNameEdited) return;

    final suggestion = (await _placeSearchService.describeLocation(
      LatLng(position.latitude, position.longitude),
    )).trim();

    if (!mounted || suggestion.isEmpty) return;

    if (_locationNameEdited) {
      // The citizen started typing while the lookup ran.
      _offerSuggestedName(suggestion);
      return;
    }

    setState(() {
      _locationNameController.text = suggestion;
    });
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_isPickingPhoto) return;

    // Leaving a text field focused while the system picker is open makes
    // Flutter restore that focus (and reopen the keyboard) on return.
    _dismissKeyboard();

    setState(() => _isPickingPhoto = true);

    try {
      final image = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );

      if (!mounted) return;

      if (image != null) {
        final bytes = await image.readAsBytes();

        if (!mounted) return;

        setState(() {
          _photo = image;
          _photoBytes = bytes;
        });
      }
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not select image: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        // The photo sheet restores the previously focused node when it is
        // dismissed, which would reopen the keyboard over the form.
        _dismissKeyboard();
        setState(() => _isPickingPhoto = false);
      }
    }
  }

  Future<void> _showPhotoOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add photo evidence',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Show the civic problem clearly.',
                  style: TextStyle(color: _muted),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined, color: _navy),
                  title: const Text('Take a photo'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickPhoto(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library_outlined,
                    color: _navy,
                  ),
                  title: const Text('Choose from gallery'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickPhoto(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    // Dismissing the sheet restores whatever was focused before it opened,
    // which would reopen the keyboard over the form.
    if (mounted) _dismissKeyboard();
  }

  Future<void> _submitForm() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      // Focus is only requested here, after an explicit submit, so an invalid
      // description never steals focus while the rest of the form is filled in.
      _focusFirstInvalidField();
      return;
    }

    if (_photo == null) {
      _showMessage('Please attach at least one photo as evidence.');
      return;
    }

    if (!_hasProblemLocation) {
      _showMessage('Please select the problem location on the map.');
      return;
    }

    // Checked last so the citizen always hears about the missing photo and
    // map point before a partly typed location name.
    final locationName = _locationNameController.text.trim();
    if (locationName.length < 2) {
      setState(() {
        _locationNameError = locationName.isEmpty
            ? 'Please enter a location name, for example "Near the town '
                  'hall".'
            : 'Please enter at least 2 characters.';
      });
      _focusLocationName();
      return;
    }

    final landmark = _landmarkController.text.trim();

    setState(() => _isSubmitting = true);

    final repository = ReportScope.read(context);

    try {
      final report = await repository.submitReport(
        category: _selectedCategory!,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        locationLabel: locationName,
        latitude: _problemLatitude!,
        longitude: _problemLongitude!,
        landmark: landmark.isEmpty ? null : landmark,
        photoBytes: _photoBytes,
        photoExtension: _photoExtension(_photo),
      );

      if (!mounted) return;

      await showReportSavedDialog(context, report);
    } catch (error) {
      if (!mounted) return;
      _showMessage(_submissionFailureMessage(error));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Words a failed submission according to how certain the failure is.
  ///
  /// A timeout or lost connection is genuinely ambiguous: the request may have
  /// reached the city even though the app never saw the response. In that case
  /// we must not claim nothing was sent — we point the citizen at My Reports so
  /// they can check before resubmitting and accidentally filing a duplicate.
  /// Definite rejections (bad payload, expired session, missing record) are safe
  /// to report as not submitted.
  String _submissionFailureMessage(Object error) {
    final failure = error is ApiException ? error.failure : null;
    switch (failure) {
      case ApiFailure.badRequest:
      case ApiFailure.unauthorized:
      case ApiFailure.forbidden:
      case ApiFailure.notFound:
        return 'Your report could not be submitted. '
            'Please review the details and try again. ($error)';
      case ApiFailure.network:
      case ApiFailure.timeout:
      case ApiFailure.server:
      case ApiFailure.invalidResponse:
      case ApiFailure.unknown:
      case null:
        return 'We could not confirm whether your report reached the city. '
            'Please check My Reports before trying again, so you do not file '
            'it twice. ($error)';
    }
  }

  String _photoExtension(XFile? photo) {
    if (photo == null) return 'jpg';
    final extension = p.extension(photo.name).replaceFirst('.', '');
    return extension.isEmpty ? 'jpg' : extension;
  }

  /// Moves focus to the first field that failed validation.
  ///
  /// This is the only place in the form that requests focus, so the keyboard
  /// never reopens as a side effect of choosing a photo or a location.
  void _focusFirstInvalidField() {
    if (_selectedCategory == null) return;

    if (_titleController.text.trim().length < 5) {
      _titleFocus.requestFocus();
      return;
    }

    if (_descriptionController.text.trim().length < 15) {
      _descriptionFocus.requestFocus();
    }
  }

  /// Focuses the location-name field and scrolls it into view.
  ///
  /// Used only after an explicit submit failed on that field, so the citizen
  /// can always reach it even when the keyboard covers the lower form.
  void _focusLocationName() {
    _locationNameFocus.requestFocus();

    final fieldContext = _locationNameFocus.context;
    if (fieldContext != null) {
      Scrollable.ensureVisible(
        fieldContext,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        alignment: 0.15,
      );
    }
  }

  void _showMessage(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        // SnackBars with an action persist by default, which would leave the
        // message over the form for ever; keep the usual timeout.
        persist: false,
        action: actionLabel != null && onAction != null
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationNameController.dispose();
    _landmarkController.dispose();
    _titleFocus.dispose();
    _descriptionFocus.dispose();
    _locationNameFocus.dispose();
    if (_ownsPlaceService) {
      _placeSearchService.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _navy,
        title: const Text(
          'Report an Issue',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            const Text(
              'Help make your community better.',
              style: TextStyle(color: _muted, fontSize: 14),
            ),
            const SizedBox(height: 24),
            _sectionTitle('01', 'Issue details'),
            const SizedBox(height: 16),
            _fieldLabel('Category'),
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: _inputDecoration(
                hint: 'Select an issue category',
                icon: Icons.category_outlined,
              ),
              items: _categories
                  .map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() => _selectedCategory = value);
              },
              validator: (value) =>
                  value == null ? 'Please select a category.' : null,
            ),
            const SizedBox(height: 18),
            _fieldLabel('Issue title'),
            TextFormField(
              controller: _titleController,
              focusNode: _titleFocus,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 80,
              decoration: _inputDecoration(
                hint: 'e.g. Large pothole near the junction',
                icon: Icons.edit_outlined,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a title.';
                }
                if (value.trim().length < 5) {
                  return 'Please enter at least 5 characters.';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            _fieldLabel('Description'),
            TextFormField(
              controller: _descriptionController,
              focusNode: _descriptionFocus,
              textCapitalization: TextCapitalization.sentences,
              minLines: 4,
              maxLines: 6,
              maxLength: 1000,
              decoration: _inputDecoration(
                hint: 'Describe the problem and why it needs attention...',
                icon: Icons.notes_rounded,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please describe the issue.';
                }
                if (value.trim().length < 15) {
                  return 'Please provide a little more detail.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _sectionTitle('02', 'Photo evidence'),
            const SizedBox(height: 8),
            const Text(
              'At least one photo is required to help people assess '
              'the problem.',
              style: TextStyle(color: _muted, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 14),
            _buildPhotoPicker(),

            // SECTION 03: PROBLEM LOCATION
            const SizedBox(height: 28),
            _sectionTitle('03', 'Problem location'),
            const SizedBox(height: 8),
            const Text(
              'Tell us where the problem is located.',
              style: TextStyle(color: _muted, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 14),

            // A. COORDINATES — the exact point under the pin.
            InkWell(
              onTap: _openLocationPicker,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration:
                    _inputDecoration(
                      hint: 'Tap to choose a place on the map',
                      icon: Icons.location_on_outlined,
                    ).copyWith(
                      suffixIcon: const Icon(Icons.map_outlined, color: _teal),
                    ),
                child: Text(
                  _hasProblemLocation
                      ? '${_problemLatitude!.toStringAsFixed(6)}, '
                            '${_problemLongitude!.toStringAsFixed(6)}'
                      : 'Choose problem location',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _hasProblemLocation ? _navy : _muted,
                    fontSize: 13,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // B. LOCATION NAME — the human readable place or address.
            _fieldLabel('Location name'),
            TextFormField(
              controller: _locationNameController,
              focusNode: _locationNameFocus,
              textCapitalization: TextCapitalization.words,
              maxLength: 120,
              decoration: _inputDecoration(
                hint: 'e.g. Kulikawn, Aizawl',
                icon: Icons.place_outlined,
              ).copyWith(errorText: _locationNameError),
              onChanged: (value) {
                setState(() {
                  _locationNameError = null;
                  // Clearing the field hands it back to the automatic
                  // suggestion; anything typed is treated as a manual edit
                  // and is never overwritten.
                  _locationNameEdited = value.trim().isNotEmpty;
                });
              },
            ),
            const SizedBox(height: 6),
            const Text(
              'The place or address shown in your report.',
              style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
            ),

            const SizedBox(height: 16),

            // C. LANDMARK — optional extra directions.
            _fieldLabel('Landmark (optional)'),
            TextFormField(
              controller: _landmarkController,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 160,
              decoration: _inputDecoration(
                hint: 'e.g. Near the community hall',
                icon: Icons.near_me_outlined,
              ),
              onChanged: (_) {
                // Reviewing or rewriting the landmark resolves the hint.
                if (_landmarkMayBeStale) {
                  setState(() => _landmarkMayBeStale = false);
                }
              },
            ),
            const SizedBox(height: 6),
            if (_landmarkMayBeStale &&
                _landmarkController.text.trim().isNotEmpty)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: Color(0xFFB54708),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'The point moved — check that this landmark still '
                      'applies.',
                      style: TextStyle(
                        color: Color(0xFFB54708),
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              )
            else
              const Text(
                'Optional: extra directions to pinpoint the spot.',
                style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
              ),

            const SizedBox(height: 14),

            if (_hasProblemLocation) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openLocationPicker,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Change location on map'),
                  style: _outlinedButtonStyle,
                ),
              ),
              const SizedBox(height: 10),
            ],

            OutlinedButton.icon(
              onPressed: _isGettingLocation ? null : _getCurrentLocation,
              icon: const Icon(Icons.my_location_rounded),
              label: Text(
                _isGettingLocation
                    ? 'Getting location...'
                    : 'Use my current location',
              ),
              style: _outlinedButtonStyle,
            ),

            if (_hasProblemLocation) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: _teal,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Problem location selected: '
                      '${_problemLatitude!.toStringAsFixed(6)}, '
                      '${_problemLongitude!.toStringAsFixed(6)}',
                      style: const TextStyle(
                        color: Color(0xFF027A48),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // SUBMIT BUTTON
            const SizedBox(height: 28),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _isPickingPhoto || _isSubmitting
                    ? null
                    : _submitForm,
                icon: _isSubmitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _navy,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(_isSubmitting ? 'Saving...' : 'Submit Report'),
                style: FilledButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: _navy,
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Submitted reports are sent to the city. The photo you attach '
              'is uploaded with your report and stored by the backend.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 11, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoPicker() {
    if (_photo != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _photoBytes != null
                  ? Image.memory(
                      _photoBytes!,
                      height: 210,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        height: 150,
                        alignment: Alignment.center,
                        color: _background,
                        child: const Text('Could not display this image.'),
                      ),
                    )
                  : Container(
                      height: 150,
                      alignment: Alignment.center,
                      color: _background,
                      child: const CircularProgressIndicator(),
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: _teal, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Photo attached',
                    style: TextStyle(color: _navy, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: _isPickingPhoto ? null : _showPhotoOptions,
                  child: const Text('Change'),
                ),
                IconButton(
                  tooltip: 'Remove photo',
                  onPressed: () {
                    setState(() {
                      _photo = null;
                      _photoBytes = null;
                    });
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: _isPickingPhoto ? null : _showPhotoOptions,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _teal, width: 1.3),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _teal.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_a_photo_outlined,
                size: 30,
                color: _navy,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Add photo evidence *',
              style: TextStyle(
                color: _navy,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Take a photo or choose one from your gallery',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
            ),
            if (_isPickingPhoto) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String number, String title) {
    return Row(
      children: [
        Container(
          height: 32,
          width: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _navy,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: _teal,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            color: _navy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: _navy,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _muted, fontSize: 12),
      prefixIcon: Icon(icon, color: _muted, size: 20),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _teal, width: 1.5),
      ),
    );
  }
}
