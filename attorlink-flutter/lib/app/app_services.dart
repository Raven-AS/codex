import 'package:flutter/widgets.dart';

import '../core/network/api_client.dart';
import '../features/auth/domain/session_controller.dart';
import 'live_updates.dart';

/// Makes the application-owned client available to future feature repositories.
class AppServices extends InheritedWidget {
  const AppServices({
    super.key,
    required this.session,
    required super.child,
    this.live,
  });

  final SessionController session;
  final LiveUpdates? live;
  static LiveUpdates? liveOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppServices>()?.live;
  ApiClient get api => session.api;

  static ApiClient apiOf(BuildContext context) {
    final services = context.dependOnInheritedWidgetOfExactType<AppServices>();
    assert(services != null, 'AppServices is missing from the widget tree');
    return services!.api;
  }

  static SessionController sessionOf(BuildContext context) {
    final services = context.dependOnInheritedWidgetOfExactType<AppServices>();
    assert(services != null, 'AppServices is missing from the widget tree');
    return services!.session;
  }

  @override
  bool updateShouldNotify(AppServices oldWidget) =>
      session != oldWidget.session || live != oldWidget.live;
}
