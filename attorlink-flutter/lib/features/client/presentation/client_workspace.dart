import '../../settings/data/settings_repository.dart';
import '../../settings/presentation/settings_screens.dart';
import '../../calls/presentation/call_screens.dart';

import 'package:flutter/material.dart';

import '../../../app/app_shell.dart';
import '../../../app/app_services.dart';
import '../../notifications/data/notification_repository.dart';
import '../../notifications/presentation/notification_inbox.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/domain/session_controller.dart';
import '../../messaging/data/chat_repository.dart';
import '../../messaging/presentation/chat_inbox.dart';
import '../../community/data/community_repository.dart';
import '../../community/presentation/community_screen.dart';
import '../../discovery/data/discovery_repository.dart';
import '../../discovery/presentation/discovery_screen.dart';
import '../data/client_repository.dart';
import '../domain/client_models.dart';
import 'address_editor.dart';
import 'client_widgets.dart';
import 'photo_editor.dart';
import 'preferences_editor.dart';
import 'profile_editor.dart';

class ClientWorkspace extends StatefulWidget {
  const ClientWorkspace({super.key, required this.session, required this.user});
  final SessionController session;
  final AuthUser user;
  @override
  State<ClientWorkspace> createState() => _ClientWorkspaceState();
}

class _ClientWorkspaceState extends State<ClientWorkspace> {
  late final _discovery = DiscoveryRepository(widget.session.api);
  late final _chat = ChatRepository(
    widget.session.api,
    ownerId: widget.user.id,
    sessionGeneration: () => widget.session.generation,
    accessChanges: widget.session.changes,
    live: AppServices.liveOf(context),
    currentUser: () =>
        widget.session.state.status == SessionStatus.authenticated
        ? widget.session.state.user
        : null,
  );
  late final _community = CommunityRepository(
    widget.session.api,
    ownerId: widget.user.id,
    sessionGeneration: () => widget.session.generation,
    accessChanges: widget.session.changes,
    currentUser: () =>
        widget.session.state.status == SessionStatus.authenticated
        ? widget.session.state.user
        : null,
  );
  late final _notifications = NotificationRepository(
    _chat.api,
    ownerId: _chat.ownerId,
    sessionGeneration: () => widget.session.generation,
    currentUser: _chat.currentUser,
    accessChanges: _chat.accessChanges,
    live: _chat.live,
  );
  late final _repository = ClientRepository(
    widget.session.api,
    ownerId: widget.user.id,
    sessionGeneration: () => widget.session.generation,
    currentUser: () =>
        widget.session.state.status == SessionStatus.authenticated
        ? widget.session.state.user
        : null,
  );
  ClientProfile? _profile;
  ApiException? _error;
  bool _loading = true;
  int _profileRevision = 0;
  bool? _onboarding;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _community.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final revision = ++_profileRevision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await _repository.profile();
      if (mounted && revision == _profileRevision) {
        setState(() {
          _profile = profile;
          _onboarding ??= profile.status == 'DRAFT';
        });
      }
    } on ApiException catch (error) {
      if (mounted && revision == _profileRevision) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && revision == _profileRevision) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshProfile() async {
    final revision = ++_profileRevision;
    final profile = await _repository.profile();
    if (mounted && revision == _profileRevision) {
      setState(() => _profile = profile);
    }
  }

  void _next() => setState(() => _step++);

  @override
  Widget build(BuildContext context) {
    if (widget.user.role != UserRole.client ||
        widget.user.status != UserStatus.active) {
      return const Scaffold(
        body: ErrorView(
          error: ApiException(
            kind: ApiErrorKind.forbidden,
            message: 'Client access is required.',
          ),
        ),
      );
    }
    if (_loading || _error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Client profile'),
          actions: [
            TextButton(
              onPressed: widget.session.logout,
              child: const Text('Sign out'),
            ),
          ],
        ),
        body: _loading
            ? const LoadingView()
            : ErrorView(error: _error!, onRetry: _load),
      );
    }
    final profile = _profile!;
    if (_onboarding == true) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Client setup · ${_step + 1} of 4'),
          actions: [
            TextButton(
              onPressed: widget.session.logout,
              child: const Text('Sign out'),
            ),
          ],
        ),
        body: SafeArea(
          child: switch (_step) {
            0 => ProfileEditor(
              repository: _repository,
              profile: profile,
              onboarding: true,
              onSaved: (saved) {
                setState(() {
                  ++_profileRevision;
                  _profile = saved;
                });
                _next();
              },
            ),
            1 => AddressEditor(
              repository: _repository,
              onboarding: true,
              onSaved: _next,
              onSkip: _next,
            ),
            2 => PreferencesEditor(
              repository: _repository,
              onSaved: _next,
              onSkip: _next,
            ),
            _ => PhotoEditor(
              repository: _repository,
              photo: profile.photo,
              onChanged: _refreshProfile,
              onContinue: () => setState(() => _onboarding = false),
            ),
          },
        ),
      );
    }
    return AppShell(
      discovery: DiscoveryScreen(repository: _discovery, community: _community),
      community: CommunityScreen(repository: _community),
      messaging: ChatInboxScreen(repository: _chat),
      settingsAction: SettingsEntry(
        repository: SettingsRepository.forSession(widget.session),
      ),
      callAction: CallsEntry(chat: _chat),
      notificationAction: NotificationEntry(
        repository: _notifications,
        chat: _chat,
        community: _community,
      ),
      account: _ClientAccount(
        repository: _repository,
        profile: profile,
        session: widget.session,
        onProfileSaved: (saved) => setState(() {
          ++_profileRevision;
          _profile = saved;
        }),
        onPhotoChanged: _refreshProfile,
      ),
    );
  }
}

enum _ClientSection { overview, profile, address, preferences, photo }

class _ClientAccount extends StatefulWidget {
  const _ClientAccount({
    required this.repository,
    required this.profile,
    required this.session,
    required this.onProfileSaved,
    required this.onPhotoChanged,
  });
  final ClientRepository repository;
  final ClientProfile profile;
  final SessionController session;
  final ValueChanged<ClientProfile> onProfileSaved;
  final Future<void> Function() onPhotoChanged;
  @override
  State<_ClientAccount> createState() => _ClientAccountState();
}

class _ClientAccountState extends State<_ClientAccount> {
  _ClientSection _section = _ClientSection.overview;
  String? _message;
  void _open(_ClientSection section) => setState(() {
    _section = section;
    _message = null;
  });
  void _saved(String message) => setState(() {
    _section = _ClientSection.overview;
    _message = message;
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(
          spacing: 12,
          alignment: WrapAlignment.center,
          children: [
            if (_section != _ClientSection.overview)
              TextButton.icon(
                onPressed: () => _open(_ClientSection.overview),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Profile overview'),
              ),
            TextButton(
              onPressed: widget.session.logout,
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Semantics(liveRegion: true, child: Text(_message!)),
        ),
      Expanded(
        child: switch (_section) {
          _ClientSection.overview => _Overview(
            key: ValueKey(widget.profile),
            repository: widget.repository,
            profile: widget.profile,
            loginEmail: widget.session.state.user!.email,
            onOpen: _open,
          ),
          _ClientSection.profile => ProfileEditor(
            profile: widget.profile,
            repository: widget.repository,
            onSaved: (saved) {
              widget.onProfileSaved(saved);
              _saved('Profile saved.');
            },
          ),
          _ClientSection.address => AddressEditor(
            repository: widget.repository,
            onSaved: () => _saved('Address saved.'),
          ),
          _ClientSection.preferences => PreferencesEditor(
            repository: widget.repository,
            onSaved: () => _saved('Legal preferences saved.'),
          ),
          _ClientSection.photo => PhotoEditor(
            repository: widget.repository,
            photo: widget.profile.photo,
            onChanged: widget.onPhotoChanged,
          ),
        },
      ),
    ],
  );
}

class _Overview extends StatelessWidget {
  const _Overview({
    super.key,
    required this.repository,
    required this.profile,
    required this.loginEmail,
    required this.onOpen,
  });
  final ClientRepository repository;
  final ClientProfile profile;
  final String loginEmail;
  final ValueChanged<_ClientSection> onOpen;
  @override
  Widget build(BuildContext context) => ClientFormLayout(
    title: 'Client profile',
    children: [
      Center(
        child: SizedBox.square(
          dimension: 120,
          child: ProfilePhoto(url: profile.photo),
        ),
      ),
      Text(
        profile.displayName.isEmpty ? 'Your profile' : profile.displayName,
        style: Theme.of(context).textTheme.titleLarge,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 16),
      Text('Sign-in email: $loginEmail'),
      Text('Profile status: ${profile.status}'),
      for (final entry in {
        'firstName': 'First name',
        'lastName': 'Last name',
        'dateOfBirth': 'Date of birth',
        'gender': 'Gender',
        'phone': 'Profile phone',
        'email': 'Profile contact email',
        'occupation': 'Occupation',
      }.entries)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(entry.value),
          subtitle: Text(
            profile.text(entry.key)?.isNotEmpty == true
                ? profile.text(entry.key)!
                : 'Not provided',
          ),
        ),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: () => onOpen(_ClientSection.profile),
            child: const Text('Edit profile'),
          ),
          OutlinedButton(
            onPressed: () => onOpen(_ClientSection.photo),
            child: const Text('Manage photo'),
          ),
        ],
      ),
      const Divider(height: 32),
      Text('Address', style: Theme.of(context).textTheme.titleLarge),
      SizedBox(
        height: 250,
        child: ClientLoader<ClientAddress?>(
          load: repository.address,
          builder: (address) => SingleChildScrollView(
            child: address == null
                ? const Text('No address has been saved.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final key in [
                        ...ClientAddress.textKeys,
                        'latitude',
                        'longitude',
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '${switch (key) {
                              'addressLine' => 'Address line',
                              'postalCode' => 'Postal code',
                              _ => '${key[0].toUpperCase()}${key.substring(1)}',
                            }}: ${address.text(key)?.isNotEmpty == true ? address.text(key) : 'Not provided'}',
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
      OutlinedButton(
        onPressed: () => onOpen(_ClientSection.address),
        child: const Text('Edit address'),
      ),
      const Divider(height: 32),
      Text('Legal preferences', style: Theme.of(context).textTheme.titleLarge),
      SizedBox(
        height: 250,
        child: ClientLoader<LegalPreferences>(
          load: repository.preferences,
          builder: (prefs) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in {
                  'Practice areas': prefs.practiceAreas
                      .map((v) => v.name)
                      .toList(),
                  'Jurisdictions': prefs.jurisdictions
                      .map((v) => v.name)
                      .toList(),
                  'Courts': prefs.courts.map((v) => v.name).toList(),
                  'Lawyer languages': prefs.lawyerLanguages,
                }.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '${entry.key}: ${entry.value.isEmpty ? 'None selected' : entry.value.join(', ')}',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      OutlinedButton(
        onPressed: () => onOpen(_ClientSection.preferences),
        child: const Text('Edit legal preferences'),
      ),
    ],
  );
}
