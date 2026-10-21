import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/auth_user.dart';
import '../services/profile_store.dart';
import '../state/auth_repository.dart';
import '../state/auth_scope.dart';

const Color _navy = Color(0xFF102A43);
const Color _teal = Color(0xFF13B8A6);
const Color _muted = Color(0xFF627D98);
const Color _background = Color(0xFFF5F7FA);
const Color _border = Color(0xFFE4EAF0);
const Color _danger = Color(0xFFB3261E);

/// The citizen's profile: their picture and identity at the top, followed by
/// the sign-out control.
///
/// The picture is optional and stored only on this device. It is never
/// uploaded and is not part of the account: [ProfileStore] keeps the file in
/// the app documents directory and stores only a small file-name reference.
/// Reports themselves live with the municipal backend.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.profileStore, this.imagePicker});

  /// Device-local picture storage. Injectable so widget tests never touch the
  /// platform channel or the real file system.
  final ProfileStore? profileStore;

  /// The system picker. Injectable for the same reason.
  final ImagePicker? imagePicker;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  AuthRepository? _auth;

  late final ProfileStore _store = widget.profileStore ?? ProfileStore();
  late final ImagePicker _picker = widget.imagePicker ?? ImagePicker();

  File? _avatarFile;
  bool _avatarLoadStarted = false;
  bool _isUpdatingAvatar = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _auth ??= AuthScope.read(context);

    if (!_avatarLoadStarted) {
      _avatarLoadStarted = true;
      _loadAvatar();
    }
  }

  Future<void> _loadAvatar() async {
    File? file;
    try {
      file = await _store.resolveAvatar();
    } catch (_) {
      // Unreadable storage simply means "no picture yet".
      file = null;
    }
    if (!mounted) return;
    setState(() => _avatarFile = file);
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _navy,
        automaticallyImplyLeading: false,
        title: const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          _buildHeader(auth.user),
          const SizedBox(height: 28),
          _buildSignOutCard(auth),
        ],
      ),
    );
  }

  Widget _buildHeader(AuthUser? user) {
    return Column(
      children: [
        _buildAvatar(),
        const SizedBox(height: 14),
        Text(
          user?.name ?? 'Citizen',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _navy,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 8),
        _buildLocation(user),
        if (user != null && user.email.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            user.email,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 12.5),
          ),
        ],
      ],
    );
  }

  Widget _buildAvatar() {
    return SizedBox(
      height: 118,
      width: 150,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          _buildAvatarCircle(),
          Positioned(bottom: 0, child: _buildEditBadge()),
        ],
      ),
    );
  }

  Widget _buildAvatarCircle() {
    return Container(
      height: 104,
      width: 104,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipOval(
        child: Container(
          color: _navy,
          alignment: Alignment.center,
          child: _avatarContent(),
        ),
      ),
    );
  }

  Widget _avatarContent() {
    final file = _avatarFile;
    if (file == null) return _defaultAvatar();

    return Image.file(
      file,
      key: const Key('profile-avatar-image'),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      // A picture removed from disk must degrade to the default avatar rather
      // than show a broken image.
      errorBuilder: (_, _, _) => _defaultAvatar(),
    );
  }

  Widget _defaultAvatar() {
    return const Center(
      child: Icon(
        Icons.person_rounded,
        key: Key('profile-default-avatar'),
        color: _teal,
        size: 50,
      ),
    );
  }

  Widget _buildEditBadge() {
    return Material(
      color: Colors.white,
      elevation: 2,
      shape: const StadiumBorder(side: BorderSide(color: _border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: _isUpdatingAvatar ? null : _showAvatarOptions,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_rounded, size: 15, color: _navy),
              SizedBox(width: 6),
              Text(
                'Edit',
                style: TextStyle(
                  color: _navy,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocation(AuthUser? user) {
    final line = _locationLine(user);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.location_on_outlined, size: 15, color: _muted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            line ?? 'Location not set',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
        ),
      ],
    );
  }

  static String? _locationLine(AuthUser? user) {
    final district = user?.district?.trim();
    final state = user?.state?.trim();
    final hasDistrict = district != null && district.isNotEmpty;
    final hasState = state != null && state.isNotEmpty;

    if (hasDistrict && hasState) return '$district, $state';
    if (hasDistrict) return district;
    if (hasState) return state;
    return null;
  }

  Future<void> _showAvatarOptions() async {
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
                  'Profile picture',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your picture is stored only on this device.',
                  style: TextStyle(color: _muted),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined, color: _navy),
                  title: const Text('Take a photo'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAvatar(ImageSource.camera);
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
                    _pickAvatar(ImageSource.gallery);
                  },
                ),
                if (_avatarFile != null)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline_rounded,
                      color: _danger,
                    ),
                    title: const Text(
                      'Remove picture',
                      style: TextStyle(color: _danger),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _removeAvatar();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAvatar(ImageSource source) async {
    if (_isUpdatingAvatar) return;
    setState(() => _isUpdatingAvatar = true);

    try {
      final image = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1080,
      );

      // A null result means the citizen backed out of the picker: the current
      // picture is kept exactly as it was.
      if (!mounted || image == null) return;

      final bytes = await image.readAsBytes();
      if (!mounted) return;

      await _store.saveAvatar(bytes, extension: _extensionOf(image));
      final file = await _store.resolveAvatar();
      if (!mounted) return;

      setState(() => _avatarFile = file);
    } catch (_) {
      if (!mounted) return;
      _showMessage('Could not update your profile picture. Please try again.');
    } finally {
      if (mounted) setState(() => _isUpdatingAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    if (_isUpdatingAvatar) return;
    setState(() => _isUpdatingAvatar = true);

    try {
      await _store.clearAvatar();
      if (!mounted) return;
      setState(() => _avatarFile = null);
    } catch (_) {
      if (!mounted) return;
      _showMessage('Could not remove your profile picture. Please try again.');
    } finally {
      if (mounted) setState(() => _isUpdatingAvatar = false);
    }
  }

  static String _extensionOf(XFile image) {
    final path = image.path;
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'jpg';
    return path.substring(dot + 1);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Widget _buildSignOutCard(AuthRepository auth) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Signed in on this device',
            style: TextStyle(color: _navy, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Signing out removes the saved sign-in from this device.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: auth.isBusy ? null : () => _confirmSignOut(auth),
              icon: const Icon(Icons.logout_rounded, size: 19),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _danger,
                side: BorderSide(color: _danger.withValues(alpha: 0.35)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(AuthRepository auth) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Sign out?',
          style: TextStyle(color: _navy, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'You will need your email and password to sign in again.',
          style: TextStyle(color: _muted, fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _navy, fontWeight: FontWeight.w700),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: _danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await auth.signOut();

    if (!mounted) return;
    // Discard any route opened while signed in so the back button cannot
    // return to an authenticated screen.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}
