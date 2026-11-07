import '../../settings/data/settings_repository.dart';
import '../../settings/presentation/settings_screens.dart';
import '../../boosts/data/boost_repository.dart';
import '../../boosts/presentation/boost_screens.dart';
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
import '../../client/presentation/client_widgets.dart';
import '../../client/presentation/photo_editor.dart';
import '../data/lawyer_repository.dart';
import '../domain/lawyer_models.dart';
import '../domain/lawyer_validation.dart';
import 'bar_council_editor.dart';
import 'council_documents.dart';
import 'lawyer_profile_editor.dart';
import 'verification_panel.dart';
import '../practice/data/practice_repository.dart';
import '../practice/presentation/practice_hub.dart';
import '../qualifications/data/qualifications_repository.dart';
import '../qualifications/presentation/qualifications_hub.dart';

enum LawyerSection {
  overview('Overview'),
  personal('Personal'),
  professional('Professional'),
  images('Photos'),
  council('Bar Council'),
  documents('Documents'),
  verification('Verification'),
  qualifications('Qualifications'),
  practice('Practice'),
  boosts('Boosts');

  const LawyerSection(this.label);
  final String label;
}

class LawyerWorkspace extends StatefulWidget {
  const LawyerWorkspace({super.key, required this.session, required this.user});
  final SessionController session;
  final AuthUser user;
  @override
  State<LawyerWorkspace> createState() => _LawyerWorkspaceState();
}

class _LawyerWorkspaceState extends State<LawyerWorkspace> {
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
  late final _repository = LawyerRepository(
    widget.session.api,
    ownerId: widget.user.id,
    sessionGeneration: () => widget.session.generation,
    currentUser: () =>
        widget.session.state.status == SessionStatus.authenticated
        ? widget.session.state.user
        : null,
  );
  LawyerSnapshot? _snapshot;
  ApiException? _error;
  bool _loading = true;
  int _profileRevision = 0;
  bool? _onboarding;
  int _step = 0;
  LawyerSection _section = LawyerSection.overview;
  String? _message;
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
      final snapshot = await _repository.snapshot();
      if (mounted && revision == _profileRevision) {
        setState(() {
          _snapshot = snapshot;
          _onboarding ??= snapshot.profile.status == 'DRAFT';
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

  Future<void> _refreshSnapshot() async {
    final revision = ++_profileRevision;
    final snapshot = await _repository.snapshot();
    if (mounted && revision == _profileRevision) {
      setState(() => _snapshot = snapshot);
    }
  }

  void _open(LawyerSection section) => setState(() {
    _section = section;
    _message = null;
  });
  void _profileSaved(LawyerProfile profile) => setState(() {
    ++_profileRevision;
    _snapshot = LawyerSnapshot(profile, _snapshot!.barCouncil);
    if (_onboarding == true) {
      _step++;
    } else {
      _section = LawyerSection.overview;
      _message = 'Information saved.';
    }
  });
  void _councilSaved(BarCouncilRecord record) => setState(() {
    ++_profileRevision;
    _snapshot = LawyerSnapshot(_snapshot!.profile, record);
    if (_onboarding == true) {
      _step = 3;
    } else {
      _section = LawyerSection.overview;
      _message = 'Bar Council record saved.';
    }
  });
  Widget _verification() => VerificationPanel(
    repository: _repository,
    onSnapshot: (snapshot) {
      if (mounted) {
        setState(() {
          ++_profileRevision;
          _snapshot = snapshot;
        });
      }
    },
    onEditPersonal: () {
      if (_onboarding == true) {
        setState(() => _step = 0);
      } else {
        _open(LawyerSection.personal);
      }
    },
    onEditProfessional: () {
      if (_onboarding == true) {
        setState(() => _step = 1);
      } else {
        _open(LawyerSection.professional);
      }
    },
    onEditCouncil: () {
      if (_onboarding == true) {
        setState(() => _step = 2);
      } else {
        _open(LawyerSection.council);
      }
    },
  );

  @override
  Widget build(BuildContext context) {
    if (widget.user.role != UserRole.lawyer ||
        widget.user.status != UserStatus.active) {
      return const Scaffold(
        body: ErrorView(
          error: ApiException(
            kind: ApiErrorKind.forbidden,
            message: 'An active lawyer account is required.',
          ),
        ),
      );
    }
    if (_loading || _error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Lawyer profile'),
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
    final snapshot = _snapshot!;
    if (_onboarding == true) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Lawyer setup · ${_step + 1} of 4'),
          actions: [
            TextButton(
              onPressed: widget.session.logout,
              child: const Text('Sign out'),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: switch (_step) {
                  0 => LawyerProfileEditor(
                    key: const ValueKey('onboarding-personal'),
                    repository: _repository,
                    profile: snapshot.profile,
                    personal: true,
                    onSaved: _profileSaved,
                    onboarding: true,
                  ),
                  1 => LawyerProfileEditor(
                    key: const ValueKey('onboarding-professional'),
                    repository: _repository,
                    profile: snapshot.profile,
                    personal: false,
                    onSaved: _profileSaved,
                    onboarding: true,
                  ),
                  2 => BarCouncilEditor(
                    repository: _repository,
                    onSaved: _councilSaved,
                    onboarding: true,
                  ),
                  _ => _verification(),
                },
              ),
              TextButton(
                onPressed: () => setState(() => _onboarding = false),
                child: const Text('Continue to lawyer account'),
              ),
            ],
          ),
        ),
      );
    }
    return AppShell(
      discovery: DiscoveryScreen(
        repository: _discovery,
        community: _community,
        refreshRevision: _profileRevision,
      ),
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
      initialDestination: AppDestination.account,
      account: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                for (final section in LawyerSection.values)
                  ChoiceChip(
                    label: Text(section.label),
                    selected: _section == section,
                    onSelected: (_) => _open(section),
                  ),
                TextButton(
                  onPressed: widget.session.logout,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
          if (_message != null)
            Semantics(liveRegion: true, child: Text(_message!)),
          Expanded(
            child: switch (_section) {
              LawyerSection.overview => _LawyerOverview(
                snapshot: snapshot,
                email: widget.user.email,
                onOpen: _open,
                onRefresh: _load,
              ),
              LawyerSection.personal => LawyerProfileEditor(
                key: const ValueKey('personal'),
                repository: _repository,
                profile: snapshot.profile,
                personal: true,
                onSaved: _profileSaved,
              ),
              LawyerSection.professional => LawyerProfileEditor(
                key: const ValueKey('professional'),
                repository: _repository,
                profile: snapshot.profile,
                personal: false,
                onSaved: _profileSaved,
              ),
              LawyerSection.council => BarCouncilEditor(
                repository: _repository,
                onSaved: _councilSaved,
              ),
              LawyerSection.documents => CouncilDocuments(
                repository: _repository,
                onEditRecord: () => _open(LawyerSection.council),
                onChanged: (record) => setState(() {
                  ++_profileRevision;
                  _snapshot = LawyerSnapshot(_snapshot!.profile, record);
                }),
              ),
              LawyerSection.verification => _verification(),
              LawyerSection.boosts => BoostHub(
                repository: BoostRepository(
                  _repository,
                  accessChanges: widget.session.changes,
                ),
              ),
              LawyerSection.practice => PracticeHub(
                repository: PracticeRepository(_repository),
              ),
              LawyerSection.qualifications => QualificationsHub(
                repository: QualificationsRepository(_repository),
              ),
              LawyerSection.images => DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'Profile photo'),
                        Tab(text: 'Cover photo'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          for (final cover in [false, true])
                            PhotoEditor.forUpload(
                              key: ValueKey(cover),
                              title: cover ? 'Cover photo' : 'Profile photo',
                              photo: snapshot.profile.text(
                                cover ? 'coverPhoto' : 'profilePhoto',
                              ),
                              upload: (photo) async =>
                                  (await _repository.uploadPhoto(
                                    photo,
                                    cover: cover,
                                  )).url,
                              remove: () async =>
                                  (await _repository.removePhoto(cover: cover))
                                      .url,
                              onChanged: _refreshSnapshot,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _LawyerOverview extends StatelessWidget {
  const _LawyerOverview({
    required this.snapshot,
    required this.email,
    required this.onOpen,
    required this.onRefresh,
  });
  final LawyerSnapshot snapshot;
  final String email;
  final ValueChanged<LawyerSection> onOpen;
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) => ClientFormLayout(
    title: 'Lawyer profile',
    children: [
      if (snapshot.profile.text('coverPhoto') != null)
        SizedBox(
          height: 140,
          child: ProfilePhoto(url: snapshot.profile.text('coverPhoto')),
        ),
      Center(
        child: SizedBox.square(
          dimension: 100,
          child: ProfilePhoto(url: snapshot.profile.text('profilePhoto')),
        ),
      ),
      Text(
        snapshot.profile.displayName.isEmpty
            ? 'Your lawyer profile'
            : snapshot.profile.displayName,
        style: Theme.of(context).textTheme.titleLarge,
        textAlign: TextAlign.center,
      ),
      Text('Sign-in email: $email'),
      Text('Profile verification: ${snapshot.profile.status}'),
      if (snapshot.profile.text('rejectionReason')?.isNotEmpty == true)
        SelectableText(
          'Review feedback: ${snapshot.profile.text('rejectionReason')}',
        ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () => onOpen(LawyerSection.verification),
        child: const Text('Verification status and checklist'),
      ),
      OutlinedButton(
        onPressed: onRefresh,
        child: const Text('Refresh profile and status'),
      ),
      for (final key in [
        ...LawyerProfile.personalKeys,
        ...LawyerProfile.professionalKeys,
      ])
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(LawyerValidation.labels[key]!),
          subtitle: Text(
            snapshot.profile.text(key)?.isNotEmpty == true
                ? snapshot.profile.text(key)!
                : 'Not provided',
          ),
        ),
      const Divider(),
      Text('Bar Council record', style: Theme.of(context).textTheme.titleLarge),
      Text(
        snapshot.barCouncil == null
            ? 'No registration record saved.'
            : 'Record status: ${snapshot.barCouncil!.status}',
      ),
      if (snapshot.barCouncil?.text('rejectionReason')?.isNotEmpty == true)
        SelectableText(
          'Record feedback: ${snapshot.barCouncil!.text('rejectionReason')}',
        ),
      if (snapshot.barCouncil != null) ...[
        for (final key in BarCouncilRecord.informationKeys)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(LawyerValidation.labels[key]!),
            subtitle: Text(
              snapshot.barCouncil!.text(key)?.isNotEmpty == true
                  ? snapshot.barCouncil!.text(key)!
                  : 'Not provided',
            ),
          ),
        if (snapshot.barCouncil!.text('verifiedAt') != null)
          Text(
            'Record verified at: ${snapshot.barCouncil!.text('verifiedAt')}',
          ),
        if (snapshot.barCouncil!.text('verifiedBy') != null)
          Text(
            'Record verified by: ${snapshot.barCouncil!.text('verifiedBy')}',
          ),
      ],
      OutlinedButton(
        onPressed: () => onOpen(LawyerSection.council),
        child: const Text('Manage Bar Council registration'),
      ),
      OutlinedButton(
        onPressed: () => onOpen(LawyerSection.documents),
        child: const Text('Manage Bar Council documents'),
      ),
    ],
  );
}
