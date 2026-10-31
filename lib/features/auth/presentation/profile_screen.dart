import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../app/connectly_theme.dart';
import '../../../app/local_data_scope.dart';
import '../../discovery/presentation/location_sheet.dart';
import '../data/profile_repository.dart';
import '../domain/auth_models.dart';
import 'auth_scope.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({this.repository, this.pickPhoto, super.key});

  final ProfileRepository? repository;
  final Future<Uint8List?> Function()? pickPhoto;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  ProfileRepository? _repository;
  String? _userId;
  LocalProfile? _profile;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _bio = TextEditingController();
  bool _active = false;
  bool _loading = false;
  bool _busy = false;
  bool _editing = false;
  String? _error;
  int _revision = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = AuthScope.maybeOf(context)?.user?.id;
    if (_userId != userId ||
        (_repository == null && widget.repository != null)) {
      _revision++;
      _userId = userId;
      _repository = widget.repository ??
          (userId == null
              ? null
              : LocalDataScope.of(context).profileFor(userId));
      _profile = null;
      _error = null;
      _editing = false;
      _active = false;
    }
    final active = TickerMode.valuesOf(context).enabled && _repository != null;
    if (active && !_active) unawaited(_load());
    _active = active;
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await repository.load();
      if (!mounted || revision != _revision) return;
      setState(() => _profile = profile);
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() => _error = 'Could not load your profile. Try again.');
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  void _notice(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  String _message(Object error) => error is AuthException
      ? error.message
      : 'Could not save your changes. Try again.';

  Future<void> _save(Future<LocalProfile> Function(ProfileRepository) action,
      {bool refreshUser = false}) async {
    final repository = _repository;
    if (repository == null || _busy) return;
    setState(() => _busy = true);
    try {
      final profile = await action(repository);
      if (!mounted || !identical(repository, _repository)) return;
      if (refreshUser) {
        await AuthScope.maybeOf(context)?.refreshUser();
      }
      if (mounted && identical(repository, _repository)) {
        setState(() {
          _profile = profile;
          _editing = false;
        });
      }
    } catch (error) {
      if (mounted && identical(repository, _repository)) {
        _notice(_message(error));
      }
    } finally {
      if (mounted && identical(repository, _repository)) {
        setState(() => _busy = false);
      }
    }
  }

  void _startEditing() {
    final profile = _profile;
    if (profile == null) return;
    _name.text = profile.name;
    _email.text = profile.email;
    _bio.text = profile.bio;
    setState(() => _editing = true);
  }

  Future<void> _saveDetails() => _save(
        (repository) => repository.saveDetails(
            name: _name.text, email: _email.text, bio: _bio.text),
        refreshUser: true,
      );

  Future<Uint8List?> _choosePhoto() async {
    final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80);
    return picked?.readAsBytes();
  }

  Future<void> _changePhoto() async {
    final repository = _repository;
    if (repository == null || _busy) return;
    try {
      final bytes = await (widget.pickPhoto ?? _choosePhoto)();
      if (bytes == null || !mounted || !identical(repository, _repository)) {
        return;
      }
      await _save((repo) => repo.savePhoto(bytes));
    } catch (error) {
      if (mounted && identical(repository, _repository)) {
        _notice(_message(error));
      }
    }
  }

  Future<void> _editLocation() async {
    final repository = _repository;
    if (repository == null || _busy) return;
    final edit = await showModalBottomSheet<LocationEdit>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ConnectlyTheme.navy,
      showDragHandle: true,
      builder: (_) => LocationSheet(initial: _profile?.location),
    );
    if (edit == null || !mounted || !identical(repository, _repository)) return;
    if (edit.location == null) {
      await _save((repo) => repo.removeLocation());
    } else {
      await _save((repo) => repo.saveLocation(edit.location!));
    }
  }

  Future<void> _signOut() async {
    final auth = AuthScope.maybeOf(context);
    if (auth == null || _busy) return;
    setState(() => _busy = true);
    try {
      await auth.signOut();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (mounted) _notice('We couldn\'t sign you out. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleBiometrics() async {
    final auth = AuthScope.maybeOf(context);
    if (auth == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (auth.biometricsEnabled) {
        await auth.disableBiometrics();
        if (mounted) _notice('Fingerprint unlock turned off.');
      } else {
        await auth.enableBiometrics();
        if (mounted && auth.biometricsEnabled) {
          _notice('Fingerprint unlock is on for this saved session.');
        }
      }
    } catch (error) {
      if (mounted) _notice(_message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _revision++;
    _name.dispose();
    _email.dispose();
    _bio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = AuthScope.maybeOf(context)?.user != null;
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (!signedIn) ...[
                  const CircleAvatar(
                    radius: 42,
                    backgroundColor: ConnectlyTheme.surface,
                    child: Icon(Icons.person_outline,
                        size: 44, color: ConnectlyTheme.yellow),
                  ),
                  const SizedBox(height: 24),
                  const Text('You\'re exploring as a guest',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  const Text('Sign in to make this space yours.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: () => Navigator.of(context)
                        .popUntil((route) => route.isFirst),
                    child: const Text('Sign in'),
                  ),
                ] else if (_loading && profile == null) ...[
                  const Center(child: CircularProgressIndicator()),
                ] else if (_error != null && profile == null) ...[
                  Text(_error!, textAlign: TextAlign.center),
                  TextButton(onPressed: _load, child: const Text('Try again')),
                ] else if (profile != null) ...[
                  Center(
                    child: CircleAvatar(
                      radius: 52,
                      backgroundColor: ConnectlyTheme.surface,
                      backgroundImage: profile.photo == null
                          ? null
                          : MemoryImage(profile.photo!),
                      child: profile.photo == null
                          ? const Icon(Icons.person_outline,
                              size: 50, color: ConnectlyTheme.yellow)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Wrap(spacing: 8, children: [
                      TextButton.icon(
                        onPressed: _busy ? null : _changePhoto,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Choose photo'),
                      ),
                      if (profile.photo != null)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _save((repo) => repo.savePhoto(null)),
                          child: const Text('Remove photo'),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  Text(profile.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: 'Urbanist',
                          fontSize: 28,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(profile.email, textAlign: TextAlign.center),
                  if (profile.bio.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(profile.bio, textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 20),
                  if (_editing) ...[
                    TextField(
                      controller: _name,
                      maxLength: 80,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    TextField(
                      controller: _email,
                      maxLength: 254,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    TextField(
                      controller: _bio,
                      maxLength: 160,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Short bio'),
                    ),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _editing = false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _busy ? null : _saveDetails,
                        child: const Text('Save profile'),
                      ),
                    ]),
                  ] else
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _startEditing,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit profile'),
                    ),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Location',
                                style: TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            Text(profile.location == null
                                ? 'No saved location. Set one to find nearby people.'
                                : profile.location!.visible
                                    ? 'Your location is shared with local accounts.'
                                    : 'Your location is hidden from local accounts.'),
                            if (profile.location != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                  '${profile.location!.latitude.toStringAsFixed(5)}, '
                                  '${profile.location!.longitude.toStringAsFixed(5)}'),
                            ],
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _editLocation,
                              icon: const Icon(Icons.location_on_outlined),
                              label: Text(profile.location == null
                                  ? 'Set location'
                                  : 'Edit location'),
                            ),
                          ]),
                    ),
                  ),
                  if (AuthScope.maybeOf(context)?.canConfigureBiometrics ==
                      true) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Fingerprint unlock',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              const Text(
                                  'Unlock your saved session after reopening the app. Your password remains available.'),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                key: const Key('biometric_toggle'),
                                onPressed: _busy ? null : _toggleBiometrics,
                                icon: const Icon(Icons.fingerprint),
                                label: Text(AuthScope.maybeOf(context)!
                                        .biometricsEnabled
                                    ? 'Turn off fingerprint unlock'
                                    : 'Enable fingerprint unlock'),
                              ),
                              if (AuthScope.maybeOf(context)!
                                  .biometricsEnabled)
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => AuthScope.maybeOf(context)!.lock(),
                                  child: const Text('Lock now'),
                                ),
                            ]),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _signOut,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.logout_rounded),
                    label: const Text('Sign out'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
