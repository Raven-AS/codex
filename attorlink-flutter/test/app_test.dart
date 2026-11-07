import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attorlink_flutter/app/app_shell.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/shared/widgets/error_view.dart';
import 'package:attorlink_flutter/shared/widgets/loading_view.dart';

void main() {
  testWidgets('home links open existing features and retain tab state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppShell(
          discovery: Text('Live discovery section'),
          community: Text('Live community section'),
          messaging: Text('Live conversations section'),
          account: Text('Live profile section'),
        ),
      ),
    );
    expect(find.textContaining('future update'), findsNothing);
    await tester.tap(find.text('Find a lawyer'));
    await tester.pumpAndSettle();
    expect(find.text('Live discovery section'), findsOneWidget);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conversations'));
    await tester.pumpAndSettle();
    expect(find.text('Live conversations section'), findsOneWidget);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Your profile'));
    await tester.pumpAndSettle();
    expect(find.text('Live profile section'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home only offers configured feature destinations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: AppShell(account: Text('Profile'))),
    );
    expect(find.text('Your profile'), findsOneWidget);
    expect(find.text('Find a lawyer'), findsNothing);
    expect(find.text('Community feed'), findsNothing);
    expect(find.text('Conversations'), findsNothing);
  });

  testWidgets(
    'compact navigation switches destinations and survives resizing',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: AppShell()));
      expect(find.text('Welcome to Attorlink'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.text('Messages'));
      await tester.pumpAndSettle();
      expect(find.text('Messages'), findsNWidgets(2));
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        3,
      );
      await tester.tap(find.text('Discover'));
      await tester.pumpAndSettle();
      expect(find.text('Discover'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('medium width and large text render without overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: LoadingView(),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: AppShell()));
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
      false,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('error view displays safe message and invokes explicit retry', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ErrorView(
            error: const ApiException(
              kind: ApiErrorKind.network,
              message: 'Connection unavailable.',
            ),
            onRetry: () => retries++,
          ),
        ),
      ),
    );
    expect(find.text('Connection unavailable.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
  });
}
