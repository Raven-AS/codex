import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/error_view.dart';
import '../data/community_repository.dart';

/// Pushed routes must also react to logout, role, and account-status changes.
class CommunityAccess extends StatelessWidget {
  const CommunityAccess({
    super.key,
    required this.repository,
    required this.child,
  });
  final CommunityRepository repository;
  final Widget child;
  @override
  Widget build(BuildContext context) => StreamBuilder<Object?>(
    stream: repository.accessChanges,
    builder: (context, _) {
      try {
        repository.checkAccess();
      } on ApiException catch (error) {
        return Scaffold(
          appBar: AppBar(title: const Text('Community')),
          body: ErrorView(error: error),
        );
      }
      return child;
    },
  );
}
