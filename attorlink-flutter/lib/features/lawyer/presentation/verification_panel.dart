import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../client/presentation/client_widgets.dart';
import '../data/lawyer_repository.dart';
import '../domain/lawyer_models.dart';

class VerificationPanel extends StatefulWidget {
  const VerificationPanel({
    super.key,
    required this.repository,
    required this.onSnapshot,
    required this.onEditPersonal,
    required this.onEditProfessional,
    required this.onEditCouncil,
  });
  final LawyerRepository repository;
  final ValueChanged<LawyerSnapshot> onSnapshot;
  final VoidCallback onEditPersonal;
  final VoidCallback onEditProfessional;
  final VoidCallback onEditCouncil;
  @override
  State<VerificationPanel> createState() => _VerificationPanelState();
}

class _VerificationPanelState extends State<VerificationPanel> {
  LawyerSnapshot? _snapshot;
  LawyerSubmission? _submission;
  ApiException? _error;
  bool _busy = false;
  bool _needsRecheck = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await widget.repository.snapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _needsRecheck = false;
        _submission = null;
      });
      widget.onSnapshot(snapshot);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _needsRecheck || _submission != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Eligibility is advisory and always re-read before calling the server.
      final latest = await widget.repository.snapshot();
      if (!mounted) return;
      setState(() => _snapshot = latest);
      widget.onSnapshot(latest);
      if (!latest.canSubmit) return;
      final submitted = await widget.repository.submit(latest.profile.id);
      if (!mounted) return;
      setState(() {
        _submission = submitted;
        _needsRecheck = true;
      });
      // Keep the authoritative submission response visible even if this GET fails.
      final refreshed = await widget.repository.snapshot();
      if (!mounted) return;
      setState(() => _snapshot = refreshed);
      widget.onSnapshot(refreshed);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _needsRecheck = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    if (snapshot == null && _busy) {
      return const LoadingView(message: 'Checking verification requirements…');
    }
    final status = _submission?.status ?? snapshot?.profile.status;
    return ClientFormLayout(
      title: 'Verification',
      children: [
        ClientErrorNotice(error: _error),
        if (status != null) ...[
          Text(
            'Profile status: $status',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(switch (status) {
            'SUBMITTED' =>
              'Your profile has been submitted for administrator review.',
            'IN_REVIEW' => 'Your profile is under review. Keep your information current and check for feedback.',
            'VERIFIED' => 'Your profile has been verified.',
            'REJECTED' => 'Review the feedback, update your information, and check eligibility before resubmitting.',
            'EXPIRED' => 'Your verification has expired. Update your information and check whether you can submit again.',
            'SUSPENDED' => 'Your profile is suspended. Review your information and contact support if you cannot submit again.',
            _ =>
              'Complete the saved requirements below to request verification.',
          }),
        ],
        if (_submission != null)
          Semantics(liveRegion: true, child: Text(_submission!.message)),
        if (snapshot != null) ...[
          if (snapshot.profile.text('rejectionReason')?.isNotEmpty == true &&
              _submission == null)
            SelectableText(
              'Profile feedback: ${snapshot.profile.text('rejectionReason')}',
            ),
          const SizedBox(height: 16),
          _Requirement(
            label: 'First name saved',
            met: snapshot.hasFirstName,
            onEdit: _busy ? null : widget.onEditPersonal,
          ),
          _Requirement(
            label: 'Bar registration number saved',
            met: snapshot.hasBarRegistration,
            onEdit: _busy ? null : widget.onEditProfessional,
          ),
          _Requirement(
            label: 'Bar Council record saved',
            met: snapshot.hasBarCouncilRecord,
            onEdit: _busy ? null : widget.onEditCouncil,
          ),
          Text(
            'Bar Council record status: ${snapshot.barCouncil?.status ?? 'No record'}',
          ),
          if (snapshot.barCouncil?.text('rejectionReason')?.isNotEmpty == true)
            SelectableText(
              'Bar Council feedback: ${snapshot.barCouncil!.text('rejectionReason')}',
            ),
          const SizedBox(height: 16),
          const Text(
            'This checklist reflects your saved information. Documents are optional under the current submission rules. Submission requests administrator review.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed:
                _busy ||
                    _needsRecheck ||
                    _submission != null ||
                    !snapshot.canSubmit
                ? null
                : _submit,
            child: Text(_busy ? 'Please wait…' : 'Submit for verification'),
          ),
        ],
        if (_needsRecheck)
          const Text(
            'Refresh status before attempting another submission. A failed connection may still have delivered your request.',
          ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _busy ? null : _refresh,
          child: const Text('Refresh status and checklist'),
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }
}

class _Requirement extends StatelessWidget {
  const _Requirement({
    required this.label,
    required this.met,
    required this.onEdit,
  });
  final String label;
  final bool met;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      met ? Icons.check_circle_outline : Icons.radio_button_unchecked,
    ),
    title: Text(label),
    subtitle: Text(met ? 'Saved' : 'Required before submission'),
    trailing: TextButton(onPressed: onEdit, child: const Text('Edit')),
  );
}
