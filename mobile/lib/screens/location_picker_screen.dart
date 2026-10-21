import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/location_service.dart';
import '../services/place_search_service.dart';
import '../widgets/location_accuracy_dialog.dart';

const Color _navy = Color(0xFF102A43);
const Color _teal = Color(0xFF13B8A6);
const Color _muted = Color(0xFF627D98);

enum CivicMapStyle { standard, satellite }

/// The point the citizen confirmed in the picker.
///
/// [label] is the best suggestion available at confirmation time and may be
/// empty when no address could be resolved. It is a suggestion only: the
/// report form owns the editable location name.
class LocationSelection {
  const LocationSelection({
    required this.latitude,
    required this.longitude,
    required this.label,
  });

  final double latitude;
  final double longitude;
  final String label;
}

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialLabel,
    this.locationService,
    this.placeSearchService,
  });

  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialLabel;

  /// Injectable so widget tests can exercise permission and failure handling
  /// without a GPS radio or platform channels.
  final LocationService? locationService;

  /// Injectable so widget tests can exercise search success, empty, network
  /// and service-error handling without live internet access.
  final PlaceSearchService? placeSearchService;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  static const LatLng _initialMapCenter = LatLng(0, 0);

  /// How long the map has to stay still before the point under the pin is
  /// resolved. Keeps reverse geocoding off the drag path so a single pan
  /// never turns into a burst of requests.
  static const Duration _settleDelay = Duration(milliseconds: 450);

  /// Shortest query worth sending to the geocoder.
  static const int _minQueryLength = 3;

  /// Height of the centre pin glyph, used to keep its tip on the exact
  /// centre of the map viewport.
  static const double _pinSize = 52;

  late LatLng _candidate;

  CivicMapStyle _mapStyle = CivicMapStyle.standard;

  /// Suggested place name for [_candidate]. Never a fabricated value: it is
  /// either a real geocoder answer, a place the citizen picked, or empty.
  String _suggestedLabel = '';

  /// True once a point has actually been chosen: a settled map movement, a
  /// map tap, a search result or a real GPS reading. The map opens at a
  /// neutral centre, and confirming that neutral centre would silently save
  /// an invented location.
  bool _hasSelection = false;

  /// Whether [_suggestedLabel] already reflects the current candidate. Stops
  /// repeat reverse-geocoding of a point that was already resolved (or that
  /// already failed) without any movement.
  bool _labelResolved = false;

  bool _isMapReady = false;

  bool _isGettingLocation = false;
  bool _isSearching = false;
  bool _isResolvingAddress = false;

  int _addressRequestId = 0;
  int _searchRequestId = 0;

  Timer? _settleTimer;

  List<PlaceResult> _searchResults = const <PlaceResult>[];

  late final LocationService _locationService;
  late final PlaceSearchService _placeSearchService;
  late final bool _ownsPlaceService;

  @override
  void initState() {
    super.initState();

    _locationService =
        widget.locationService ?? const GeolocatorLocationService();
    _ownsPlaceService = widget.placeSearchService == null;
    _placeSearchService =
        widget.placeSearchService ?? NominatimPlaceSearchService();

    final hasInitialLocation =
        widget.initialLatitude != null && widget.initialLongitude != null;

    if (hasInitialLocation) {
      // Preserve a location passed in by the report form so reopening the
      // picker starts exactly where the citizen left off.
      _candidate = LatLng(widget.initialLatitude!, widget.initialLongitude!);
      _suggestedLabel = widget.initialLabel ?? '';
      _hasSelection = _isValidPoint(_candidate);
      _labelResolved = true;
    } else {
      _candidate = _initialMapCenter;
      _suggestedLabel = '';
      _hasSelection = false;
      _labelResolved = false;
    }
  }

  /// Centres the map on the device only when permission has already been
  /// granted. Opening the picker must never trigger the system permission
  /// prompt, because a point can always be chosen by hand on the map.
  Future<void> _centreOnDeviceIfPermitted() async {
    if (!mounted) return;

    final granted = await _locationService.hasGrantedPermission();

    if (!mounted || !granted) return;

    await _getCurrentLocation(showErrors: false, requestPermission: false);
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _searchController.dispose();
    if (_ownsPlaceService) {
      _placeSearchService.dispose();
    }
    super.dispose();
  }

  // --------------------------------------------------
  // CANDIDATE POINT
  // The point under the stationary centre pin.
  // --------------------------------------------------

  /// Guards against ever confirming a nonsense point such as (0, 0) or a
  /// non-finite value.
  static bool _isValidPoint(LatLng point) {
    if (point.latitude.isNaN || point.longitude.isNaN) return false;
    if (!point.latitude.isFinite || !point.longitude.isFinite) return false;
    if (point.latitude.abs() > 90 || point.longitude.abs() > 180) return false;
    return !(point.latitude == 0 && point.longitude == 0);
  }

  /// Makes [point] the point under the pin.
  ///
  /// [label] is passed when the caller already knows the name of the place
  /// (a search result, for example). Without it any previous suggestion is
  /// dropped, because it described a different point.
  void _setCandidate(LatLng point, {String? label}) {
    final moved = point != _candidate;

    setState(() {
      _candidate = point;
      _hasSelection = _isValidPoint(point);

      if (label != null) {
        _suggestedLabel = label;
        _labelResolved = true;
      } else if (moved) {
        _suggestedLabel = '';
        _labelResolved = false;
      }
    });
  }

  void _moveMap(LatLng point, double zoom) {
    if (!_isMapReady) return;
    _mapController.move(point, zoom);
  }

  // --------------------------------------------------
  // MAP MOVEMENT
  //
  // The pin never moves: the map moves beneath it. Every gesture is
  // debounced so reverse geocoding happens once the citizen stops panning,
  // never once per drag frame.
  // --------------------------------------------------

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    // Programmatic moves (tap, zoom buttons, search, GPS) are applied by
    // whoever triggered them; only real gestures settle through the pin.
    if (!hasGesture) return;

    _scheduleSettle();
  }

  void _scheduleSettle() {
    _settleTimer?.cancel();

    if (mounted && !_isResolvingAddress) {
      setState(() => _isResolvingAddress = true);
    }

    _settleTimer = Timer(_settleDelay, _onMapSettled);
  }

  Future<void> _onMapSettled() async {
    if (!mounted || !_isMapReady) return;

    final center = _mapController.camera.center;

    _setCandidate(center);
    await _resolveAddress(center);
  }

  void _onMapTap(TapPosition tapPosition, LatLng location) {
    _settleTimer?.cancel();

    // Put the tapped point under the centre pin so the pin stays the single
    // source of truth for the selected point.
    _moveMap(location, _isMapReady ? _mapController.camera.zoom : 16);
    _setCandidate(location);
    _resolveAddress(location);
  }

  // --------------------------------------------------
  // REVERSE GEOCODING
  // Converts coordinates into a readable address.
  // --------------------------------------------------

  Future<void> _resolveAddress(LatLng location) async {
    if (!mounted) return;

    // The point already has an answer (or already failed): never retry the
    // same coordinates automatically.
    if (_labelResolved && location == _candidate) {
      if (_isResolvingAddress) {
        setState(() => _isResolvingAddress = false);
      }
      return;
    }

    final requestId = ++_addressRequestId;

    if (!_isResolvingAddress) {
      setState(() => _isResolvingAddress = true);
    }

    try {
      // Address lookup is optional. An empty label simply means the address
      // is unavailable; the coordinates stay fully usable either way.
      final label = (await _placeSearchService.describeLocation(location))
          .trim();

      // Ignore an older response if the citizen selected
      // another location while this request was running.
      if (!mounted || requestId != _addressRequestId) return;

      setState(() {
        if (location == _candidate) {
          _suggestedLabel = label;
          _labelResolved = true;
        }
        _isResolvingAddress = false;
      });
    } catch (_) {
      // Address lookup is optional.
      // The coordinates remain usable if it fails.
      if (!mounted || requestId != _addressRequestId) return;

      setState(() {
        if (location == _candidate) {
          _suggestedLabel = '';
          _labelResolved = true;
        }
        _isResolvingAddress = false;
      });
    }
  }

  // --------------------------------------------------
  // CURRENT LOCATION
  // --------------------------------------------------

  /// Reads a fresh, high-accuracy fix and centres the pin on it.
  ///
  /// A fix that meets the accuracy target is applied straight away. A fix
  /// that does not is never applied silently: the citizen is told how
  /// accurate it really is and decides whether to use it, ask again, or pick
  /// the point on the map themselves. Every failure keeps the current
  /// selection intact and leaves manual selection fully usable.
  Future<void> _getCurrentLocation({
    bool showErrors = true,
    bool requestPermission = true,
  }) async {
    // One request at a time: a second tap while a reading is running is
    // ignored instead of stacking simultaneous GPS requests.
    if (_isGettingLocation) return;

    setState(() {
      _isGettingLocation = true;
    });

    DeviceLocation? fix;
    Object? error;
    var approximateOnly = false;

    try {
      fix = await _locationService.getCurrentLocation(
        requestPermission: requestPermission,
        // The opportunistic start-up read runs on a short budget so it can
        // never hold the radio while the citizen uses the picker.
        timeLimit: requestPermission ? null : backgroundLocationTimeLimit,
      );
      approximateOnly = await _locationService.isApproximateOnly();
    } on LocationServiceException catch (caught) {
      error = caught;
    } catch (caught) {
      error = caught;
    } finally {
      if (mounted) {
        setState(() {
          _isGettingLocation = false;
        });
      }
    }

    if (!mounted) return;

    if (error != null) {
      // A silent start-up reading that fails says nothing: the citizen has
      // not asked for a fix yet, and the manual controls are all available.
      if (showErrors) {
        _showMessage(
          error is LocationServiceException
              ? error.message
              : 'Could not read your location. You can still choose the '
                    'problem location manually on the map.',
          actionLabel: 'RETRY',
          onAction: () => _getCurrentLocation(),
        );
      }
      return;
    }

    final position = fix;
    if (position == null) return;

    final issues = position.issues(approximatePermission: approximateOnly);

    if (issues.isEmpty) {
      await _centreOnFix(position);

      // Never replace an existing selection without saying so: the pin has
      // moved, and the citizen can still adjust it before confirming.
      if (showErrors && mounted) {
        _showMessage(
          'Map centred on your current location'
          '${accuracyNote(position)}. Move the pin if needed, then confirm.',
        );
      }
      return;
    }

    // A silent start-up reading must never move the pin: an unverified fix
    // is only ever applied after the citizen has said so.
    if (!showErrors) return;

    final choice = await showLocationAccuracyDialog(
      context,
      position: position,
      issues: issues,
    );

    if (!mounted || choice == null) return;

    switch (choice) {
      case LocationFixChoice.useIt:
        await _centreOnFix(position);
        if (mounted) {
          _showMessage(
            'Using the best available location'
            '${accuracyNote(position)}. Adjust the pin before confirming.',
          );
        }
      case LocationFixChoice.retry:
        unawaited(
          _getCurrentLocation(showErrors: true, requestPermission: true),
        );
      case LocationFixChoice.chooseOnMap:
        // The map keeps its current selection and stays fully interactive.
        break;
    }
  }

  /// Makes [position] the point under the pin and resolves its address.
  Future<void> _centreOnFix(DeviceLocation position) async {
    _settleTimer?.cancel();

    final location = LatLng(position.latitude, position.longitude);

    _setCandidate(location);
    _moveMap(location, 17);
    await _resolveAddress(location);
  }

  // --------------------------------------------------
  // PLACE SEARCH
  //
  // Searching happens only on an explicit submit (keyboard search action or
  // the search button), never per keystroke. The public Nominatim API
  // forbids client-side autocomplete, so a debounce-driven request would
  // violate its usage policy and add unnecessary traffic.
  // --------------------------------------------------

  void _submitSearch() {
    final query = _searchController.text.trim();

    if (query.length < _minQueryLength) {
      setState(() {
        _searchResults = const <PlaceResult>[];
      });

      _showMessage(
        'Type at least $_minQueryLength letters to search for a place.',
      );
      return;
    }

    _searchPlaces(query);
  }

  Future<void> _searchPlaces(String query) async {
    if (!mounted) return;

    // One request at a time: a second submit while a search is running is
    // ignored instead of stacking requests on the public endpoint.
    if (_isSearching) return;

    final requestId = ++_searchRequestId;

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await _placeSearchService.search(query);

      // A response that arrives after a newer search started is dropped so
      // stale results can never replace fresher ones.
      if (!mounted || requestId != _searchRequestId) return;

      setState(() {
        _searchResults = results;
      });

      if (results.isEmpty) {
        _showMessage(
          'No places matched "$query". Try a different name, or move the '
          'map to the location directly.',
        );
      }
    } on PlaceSearchException catch (error) {
      if (!mounted || requestId != _searchRequestId) return;

      // The message already distinguishes network, service, invalid-response
      // and timeout failures from a genuine "no match", and always points
      // back to manual map selection.
      setState(() {
        _searchResults = const <PlaceResult>[];
      });

      _showMessage(error.message);
    } catch (_) {
      if (!mounted || requestId != _searchRequestId) return;

      setState(() {
        _searchResults = const <PlaceResult>[];
      });

      _showMessage(
        'Could not search for that place. You can still select it directly '
        'on the map.',
      );
    } finally {
      if (mounted && requestId == _searchRequestId) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  /// Flies to a search result so the citizen can refine it with the pin.
  ///
  /// Choosing a result never confirms it: large areas, roads and buildings
  /// still need to be narrowed down to the exact reporting point.
  void _selectSearchResult(PlaceResult result) {
    final point = LatLng(result.latitude, result.longitude);

    if (!_isValidPoint(point)) return;

    _settleTimer?.cancel();
    _addressRequestId++; // invalidate a pending reverse-geocoding request

    _moveMap(point, 17);
    _setCandidate(point, label: result.displayName);

    setState(() {
      _searchResults = const <PlaceResult>[];
      _isResolvingAddress = false;
    });

    FocusScope.of(context).unfocus();
  }

  // --------------------------------------------------
  // MAP CONTROLS
  // --------------------------------------------------

  void _zoomBy(double delta) {
    if (!_isMapReady) return;

    final camera = _mapController.camera;
    // Zooming never changes the selected point: the pin keeps reading the
    // same centre coordinates.
    _mapController.move(camera.center, camera.zoom + delta);
  }

  void _setMapStyle(CivicMapStyle style) {
    if (_mapStyle == style) return;
    setState(() => _mapStyle = style);
  }

  // --------------------------------------------------
  // CONFIRM SELECTION
  // --------------------------------------------------

  void _confirmLocation() {
    if (!_hasSelection || !_isValidPoint(_candidate)) return;

    Navigator.of(context).pop(
      LocationSelection(
        latitude: _candidate.latitude,
        longitude: _candidate.longitude,
        label: _suggestedLabel.trim(),
      ),
    );
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
        // message over the bottom panel for ever; keep the usual timeout.
        persist: false,
        action: actionLabel != null && onAction != null
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
      ),
    );
  }

  // --------------------------------------------------
  // USER INTERFACE
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _navy,
        title: const Text(
          'Choose problem location',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          // Search bar and results.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  // Typing alone must never send a request: Nominatim forbids
                  // client-side autocomplete. Results are cleared until the
                  // citizen submits explicitly.
                  onChanged: (value) {
                    if (value.trim().length < _minQueryLength &&
                        _searchResults.isNotEmpty) {
                      setState(() {
                        _searchResults = const <PlaceResult>[];
                      });
                    }
                  },
                  onSubmitted: (_) => _submitSearch(),
                  decoration: InputDecoration(
                    hintText: 'Search a road, place or landmark',
                    prefixIcon: IconButton(
                      tooltip: 'Search',
                      onPressed: _isSearching ? null : _submitSearch,
                      icon: const Icon(Icons.search, color: _muted),
                    ),
                    suffixIcon: _isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();

                              setState(() {
                                _searchResults = const <PlaceResult>[];
                              });
                            },
                            icon: const Icon(Icons.close),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),

                if (_searchResults.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black12),
                    ),
                    // A Material is required so each result row paints its
                    // own background and ink splash instead of relying on the
                    // scaffold, which the results container would hide.
                    child: Material(
                      type: MaterialType.transparency,
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final result = _searchResults[index];

                          // Nominatim returns one long, comma separated
                          // address: the first part is the place name, the
                          // rest is secondary address detail.
                          final parts = result.displayName.split(',');
                          final primary = parts.first.trim();
                          final secondary = parts.length > 1
                              ? parts.sublist(1).join(',').trim()
                              : '';

                          return ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.place_outlined,
                              color: _teal,
                            ),
                            title: Text(
                              primary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: secondary.isEmpty
                                ? null
                                : Text(
                                    secondary,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 11,
                                      height: 1.3,
                                    ),
                                  ),
                            onTap: () => _selectSearchResult(result),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Map with a stationary centre pin.
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _candidate,
                    initialZoom: _hasSelection ? 16 : 5,
                    minZoom: 3,
                    maxZoom: 19,
                    onTap: _onMapTap,
                    onPositionChanged: _onPositionChanged,
                    onMapReady: () {
                      _isMapReady = true;
                      if (!_hasSelection) {
                        _centreOnDeviceIfPermitted();
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      key: ValueKey(_mapStyle),
                      urlTemplate: _mapStyle == CivicMapStyle.satellite
                          ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                          : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.genevo.civiclens_mobile',
                      maxNativeZoom: 18,
                    ),

                    if (_mapStyle == CivicMapStyle.satellite)
                      TileLayer(
                        urlTemplate: 'https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
                        userAgentPackageName: 'com.genevo.civiclens_mobile',
                        maxNativeZoom: 18,
                      ),

                    RichAttributionWidget(
                      // Kept bottom-left so the map controls on the right can
                      // never cover the tile provider's attribution.
                      alignment: AttributionAlignment.bottomLeft,
                      attributions: [
                        TextSourceAttribution(
                          _mapStyle == CivicMapStyle.satellite
                              ? 'Imagery sources: Esri and its contributors'
                              : '© OpenStreetMap contributors',
                        ),
                      ],
                    ),
                  ],
                ),

                // The pin itself: fixed in the viewport, never attached to a
                // coordinate, so the point under it is always the point being
                // selected.
                IgnorePointer(child: Center(child: _centrePin())),

                // Map style switcher.
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 10),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _mapStyleButton(
                          icon: Icons.map_outlined,
                          label: 'Standard',
                          style: CivicMapStyle.standard,
                        ),
                        _mapStyleButton(
                          icon: Icons.satellite_alt,
                          label: 'Satellite',
                          style: CivicMapStyle.satellite,
                        ),
                      ],
                    ),
                  ),
                ),

                // Zoom and current-location controls.
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _mapControlButton(
                        icon: Icons.add,
                        tooltip: 'Zoom in',
                        onPressed: () => _zoomBy(1),
                      ),
                      const SizedBox(height: 8),
                      _mapControlButton(
                        icon: Icons.remove,
                        tooltip: 'Zoom out',
                        onPressed: () => _zoomBy(-1),
                      ),
                      const SizedBox(height: 8),
                      _mapControlButton(
                        icon: Icons.my_location,
                        tooltip: 'Use my current location',
                        showSpinner: _isGettingLocation,
                        onPressed: _isGettingLocation
                            ? null
                            : () => _getCurrentLocation(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Selected location and confirmation.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 12,
                  offset: Offset(0, -3),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'PROBLEM LOCATION',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Location progress, address status or resolved address.
                  if (_isGettingLocation)
                    Row(
                      children: [
                        const SizedBox(
                          height: 13,
                          width: 13,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Finding your location... this can take up to 30 '
                            'seconds.',
                            style: TextStyle(color: _muted, fontSize: 13),
                          ),
                        ),
                      ],
                    )
                  else if (_isResolvingAddress)
                    Row(
                      children: [
                        const SizedBox(
                          height: 13,
                          width: 13,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _hasSelection
                                ? 'Finding the address for this point...'
                                : 'Move the map so the pin marks the problem '
                                      'location...',
                            style: const TextStyle(color: _muted, fontSize: 13),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      _hasSelection
                          ? _suggestedLabel.isNotEmpty
                                ? _suggestedLabel
                                : 'Address unavailable — you can name this '
                                      'place on the report form'
                          : 'Move the map so the pin marks the problem '
                                'location, or search for a place',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                  if (_hasSelection) ...[
                    const SizedBox(height: 4),

                    // Exact point under the pin.
                    Text(
                      '${_candidate.latitude.toStringAsFixed(6)}, '
                      '${_candidate.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      // Disabled until a point has actually been chosen, so an
                      // untouched map can never confirm the neutral centre.
                      onPressed: _hasSelection && _isValidPoint(_candidate)
                          ? _confirmLocation
                          : null,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Confirm Location'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _teal,
                        foregroundColor: _navy,
                        textStyle: const TextStyle(fontWeight: FontWeight.w800),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),

                  if (_hasSelection) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'The pin marks the exact point that will be saved.',
                      style: TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------
  // CENTRE PIN
  // --------------------------------------------------

  /// The pin drawn in the middle of the map viewport.
  ///
  /// Its tip sits on the exact centre of the map, so whatever is underneath
  /// it is the point being selected.
  Widget _centrePin() {
    return Transform.translate(
      // Half the glyph height, minus the few pixels the Material icon keeps
      // between its lowest ink and the edge of its box, so the tip lands on
      // the viewport centre rather than a few pixels above it.
      offset: const Offset(0, -(_pinSize / 2 - 4)),
      child: SizedBox(
        width: _pinSize,
        height: _pinSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.location_on, size: _pinSize, color: Colors.white),
            Icon(
              Icons.location_on,
              size: _pinSize - 6,
              color: const Color(0xFFD92D20),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------
  // MAP CONTROL BUTTON
  // --------------------------------------------------

  Widget _mapControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool showSpinner = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        constraints: const BoxConstraints(minWidth: 46, minHeight: 46),
        padding: EdgeInsets.zero,
        iconSize: 22,
        color: _navy,
        icon: showSpinner
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon),
      ),
    );
  }

  // --------------------------------------------------
  // MAP STYLE BUTTON
  // --------------------------------------------------

  Widget _mapStyleButton({
    required IconData icon,
    required String label,
    required CivicMapStyle style,
  }) {
    final selected = _mapStyle == style;

    return Semantics(
      button: true,
      selected: selected,
      label: '$label map style',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _setMapStyle(style),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? _teal.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: selected ? _navy : _muted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? _navy : _muted,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
