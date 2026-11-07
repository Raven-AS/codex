import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/boosts/data/boost_platform_android.dart';
import 'package:attorlink_flutter/features/boosts/data/boost_repository.dart';
import 'package:attorlink_flutter/features/boosts/presentation/boost_screens.dart';
import 'package:attorlink_flutter/features/calls/data/call_repository.dart';
import 'package:attorlink_flutter/features/calls/domain/call_models.dart';
import 'package:attorlink_flutter/features/calls/presentation/call_screens.dart';
import 'package:attorlink_flutter/features/calls/presentation/call_forms.dart';
import 'package:attorlink_flutter/features/lawyer/data/lawyer_repository.dart';
import 'package:attorlink_flutter/features/messaging/data/chat_repository.dart';
import 'package:attorlink_flutter/features/settings/data/settings_repository.dart';
import 'package:attorlink_flutter/features/settings/presentation/settings_screens.dart';
import 'package:attorlink_flutter/features/support/data/support_repository.dart';
import 'package:attorlink_flutter/features/support/presentation/support_screens.dart';
import 'package:attorlink_flutter/shared/widgets/error_view.dart';

import 'boosts_test.dart' as boost;
import 'calls_test.dart' as call;
import 'settings_test.dart' as security;
import 'support_test.dart' as support;

// Fixtures and platform-channel doubles only; no backend or device integration.
class Harness {
  Harness(
    this.wire, {
    Future<void> Function()? before,
    Future<bool> Function(String)? recover,
  }) {
    api = ApiClient(
      config: security.config,
      transport: wire,
      accessTokenProvider: () => 'fixture',
      beforeAuthenticatedRequest: before,
      recoverAuthentication: recover,
    );
    chat = ChatRepository(
      api,
      ownerId: 7,
      currentUser: () => boost.user,
      sessionGeneration: () => generation,
    );
    calls = CallRepository(chat);
    boosts = BoostRepository(
      LawyerRepository(
        api,
        ownerId: 7,
        currentUser: () => boost.user,
        sessionGeneration: () => generation,
      ),
    );
    settings = SettingsRepository(
      api,
      ownerId: 7,
      currentUser: () => boost.user,
      sessionGeneration: () => generation,
      invalidateSession: (_) async {
        invalidations++;
      },
      recheckSession: () async {
        rechecks++;
      },
    );
    tickets = SupportRepository(
      api,
      ownerId: 7,
      currentUser: () => boost.user,
      sessionGeneration: () => generation,
    );
  }
  final call.Wire wire;
  int generation = 0, invalidations = 0, rechecks = 0;
  late final ApiClient api;
  late final ChatRepository chat;
  late final CallRepository calls;
  late final BoostRepository boosts;
  late final SettingsRepository settings;
  late final SupportRepository tickets;
}

Future<Object?> mutation(Harness h, String operation) => switch (operation) {
  'call create' => h.calls.create(recipient: 42),
  'call action' => h.calls.action(
    CallRecord.fromJson(call.record(), scheduled: false),
    'cancel',
  ),
  'call credentials' => h.calls.credentials(
    CallRecord.fromJson(call.record(), scheduled: false),
  ),
  'boost purchase' => h.boosts.purchase(2),
  'invoice PDF' => h.boosts.invoicePdf(15),
  'privacy' => h.settings.privacy(true, value: 'EVERYONE'),
  '2FA setup' => h.settings.totpSetup(),
  'password confirm' => h.settings.resetConfirm('123456'),
  'delete confirm' => h.settings.deleteConfirm('123456'),
  'revoke' => h.settings.revoke(),
  _ => h.tickets.create(
    subject: 'Fixture ticket',
    message: 'A detailed fixture issue',
  ),
};

void main() {
  for (final operation in [
    'call create',
    'call action',
    'call credentials',
    'boost purchase',
    'invoice PDF',
    'privacy',
    '2FA setup',
    'password confirm',
    'delete confirm',
    'revoke',
    'support create',
  ]) {
    test(
      '$operation cannot dispatch after token work crosses login generations',
      () async {
        late Harness h;
        var pre = 0;
        final wire = call.Wire((_) => boost.ok(boost.profile()));
        h = Harness(
          wire,
          before: () async {
            if (++pre == (operation == 'boost purchase' ? 2 : 1)) {
              h.generation++;
            }
          },
        );
        await expectLater(
          mutation(h, operation),
          throwsA(
            isA<ApiException>().having(
              (e) => e.kind,
              'kind',
              ApiErrorKind.forbidden,
            ),
          ),
        );
        expect(wire.requests.length, operation == 'boost purchase' ? 1 : 0);
        expect(h.invalidations, 0);
        expect(h.rechecks, 0);
      },
    );
  }
  test(
    '401 recovery cannot replay an old call in a replacement login',
    () async {
      late Harness h;
      final wire = call.Wire(
        (_) => const TransportResponse(statusCode: 401, body: 'Expired'),
      );
      h = Harness(
        wire,
        recover: (_) async {
          h.generation++;
          return true;
        },
      );
      await expectLater(
        h.calls.create(recipient: 42),
        throwsA(isA<ApiException>()),
      );
      expect(wire.requests.length, 1);
    },
  );
  test(
    'late security confirmations cannot invalidate a replacement session',
    () async {
      for (final operation in [
        'password confirm',
        'delete confirm',
        'revoke',
      ]) {
        final pending = Completer<TransportResponse>();
        final wire = call.Wire((_) => pending.future);
        final h = Harness(wire);
        final result = mutation(h, operation);
        final rejected = expectLater(result, throwsA(isA<ApiException>()));
        await Future<void>.delayed(Duration.zero);
        h.generation++;
        pending.complete(
          security.ok(
            operation == 'password confirm'
                ? security.history()
                : operation == 'delete confirm'
                ? 'Scheduled'
                : null,
          ),
        );
        await rejected;
        expect(h.invalidations, 0);
        expect(h.rechecks, 0);
      }
    },
  );
  test(
    'support opened from an expired settings repository stays inaccessible',
    () async {
      final h = Harness(call.Wire((_) => security.ok(null)));
      h.generation++;
      final tickets = SupportRepository(
        h.api,
        ownerId: 7,
        currentUser: () => boost.user,
        sessionGeneration: () => h.generation,
        parentAccess: h.settings.checkAccess,
      );
      await expectLater(tickets.list(), throwsA(isA<ApiException>()));
      expect(h.wire.requests, isEmpty);
    },
  );
  test(
    'call credentials must belong to the current backend media identity',
    () async {
      final h = Harness(
        call.Wire(
          (_) => call.ok({...call.credentials(), 'identity': 'user-42'}),
        ),
      );
      await expectLater(
        h.calls.credentials(
          CallRecord.fromJson(call.record(), scheduled: false),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.invalidResponse,
          ),
        ),
      );
    },
  );
  testWidgets(
    'call confirmations serialize actions and suppress polling until dismissed',
    (tester) async {
      final wire = call.Wire(
        (r) => call.ok(
          call.record(status: r.method == 'PATCH' ? 'CANCELLED' : 'INITIATED'),
        ),
      );
      final h = Harness(wire);
      await tester.pumpWidget(
        MaterialApp(home: CallForm(repository: h.calls, scheduled: false)),
      );
      expect(
        find.widgetWithText(TextFormField, 'Note (optional)'),
        findsNothing,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CallDetail(repository: h.calls, id: 9, scheduled: false),
        ),
      );
      await tester.pumpAndSettle();
      final handler = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Cancel call'),
          )
          .onPressed!;
      handler();
      handler();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      expect(wire.requests.length, 1);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(wire.requests.where((r) => r.method == 'PATCH').length, 1);
      expect(find.textContaining('Outgoing · CANCELLED'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'security confirmations do not stack or submit cleared background credentials',
    (tester) async {
      final wire = call.Wire((_) => security.ok(null));
      final h = Harness(wire);
      await tester.pumpWidget(
        MaterialApp(
          home: SecurityFlow(
            repository: h.settings,
            mode: SecurityMode.disable,
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField), 'fixture-password');
      final handler = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Disable 2FA'),
          )
          .onPressed!;
      handler();
      handler();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(wire.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'overlapping purchase pages replace the existing row by backend ID',
    (tester) async {
      final h = Harness(
        call.Wire(
          (r) => boost.ok(
            boost.page(
              [
                {
                  ...boost.monitor(),
                  'planName': r.uri.queryParameters['page'] == '0'
                      ? 'Old plan'
                      : 'Updated plan',
                },
              ],
              number: int.parse(r.uri.queryParameters['page']!),
              totalPages: 2,
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BoostListScreen(repository: h.boosts, view: BoostView.history),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Load more'));
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(find.text('Boost #9 · Updated plan'), findsOneWidget);
      expect(find.text('Boost #9 · Old plan'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'inaccessible support details discard previously displayed private content',
    (tester) async {
      var denied = false;
      final h = Harness(
        call.Wire(
          (_) => denied
              ? const TransportResponse(statusCode: 404, body: 'Missing')
              : support.ok(support.ticket()),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: SupportTicketDetail(repository: h.tickets, id: 5)),
      );
      await tester.pumpAndSettle();
      expect(find.text(support.ticket()['message']! as String), findsOneWidget);
      denied = true;
      await tester.tap(find.byTooltip('Refresh ticket status'));
      await tester.pumpAndSettle();
      expect(find.text(support.ticket()['message']! as String), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'backend validation field errors remain visible in shared error states',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorView(
              error: ApiException(
                kind: ApiErrorKind.validation,
                message: 'Validation failed',
                fieldErrors: {'subject': 'Subject exceeds limit'},
              ),
            ),
          ),
        ),
      );
      expect(find.text('subject: Subject exceeds limit'), findsOneWidget);
    },
  );
  testWidgets(
    'Android checkout/export channel contracts handle cancellation and provider failures',
    (tester) async {
      const channel = MethodChannel('attorlink/boost-platform');
      final calls = <MethodCall>[];
      var fail = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (fail) {
          throw PlatformException(code: 'WRITE', message: 'provider details');
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await openAndroidCheckout(Uri.parse(boost.demo));
      expect(calls.single.arguments, {'url': boost.demo});
      final bytes = Uint8List.fromList('%PDF-fixture'.codeUnits);
      expect(
        await saveAndroidInvoice(bytes, 'invoice.pdf'),
        'Invoice save cancelled.',
      );
      expect(calls.last.method, 'chooseInvoice');
      expect((calls.last.arguments as Map)['filename'], 'invoice.pdf');
      fail = true;
      await expectLater(
        saveAndroidInvoice(bytes, 'invoice.pdf'),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        openAndroidCheckout(Uri.parse(boost.demo)),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test(
    'late invoice bodies are rejected before PDF decoding after a new login',
    () async {
      final pending = Completer<TransportResponse>();
      final h = Harness(call.Wire((_) => pending.future));
      final result = h.boosts.invoicePdf(15);
      final rejected = expectLater(
        result,
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.forbidden,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      h.generation++;
      pending.complete(
        const TransportResponse(statusCode: 200, body: 'old account data'),
      );
      await rejected;
    },
  );
  testWidgets(
    'call rejection locks lifecycle actions and failed access refresh clears details',
    (tester) async {
      var revoked = false;
      final h = Harness(
        call.Wire(
          (r) => r.method == 'PATCH'
              ? const TransportResponse(
                  statusCode: 400,
                  body: 'Invalid transition',
                )
              : revoked
              ? const TransportResponse(
                  statusCode: 400,
                  body: 'Not a participant',
                )
              : call.ok(call.record()),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CallDetail(repository: h.calls, id: 9, scheduled: false),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel call'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Cancel call'),
            )
            .onPressed,
        isNull,
      );
      revoked = true;
      await tester.tap(find.byTooltip('Refresh call status'));
      await tester.pumpAndSettle();
      expect(find.text('Outgoing · INITIATED'), findsNothing);
      expect(find.text('Cancel call'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('revoked boost details discard the cached checkout handoff', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 2600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var revoked = false;
    final h = Harness(
      call.Wire(
        (r) => revoked
            ? const TransportResponse(statusCode: 403, body: 'Forbidden')
            : boost.ok(
                r.uri.path.endsWith('/sandbox-checkout')
                    ? boost.handoff()
                    : boost.monitor(),
              ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: BoostDetail(repository: h.boosts, id: 9)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Get sandbox checkout'));
    await tester.tap(find.text('Get sandbox checkout'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open sandbox demo'));
    expect(find.text('Open sandbox demo'), findsOneWidget);
    revoked = true;
    await tester.tap(find.byTooltip('Refresh backend status'));
    await tester.pumpAndSettle();
    expect(find.text('Open sandbox demo'), findsNothing);
    expect(find.text('Get sandbox checkout'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Android export rechecks access after picker and before sending PDF bytes',
    (tester) async {
      const channel = MethodChannel('attorlink/boost-platform');
      var allowed = true;
      final calls = <MethodCall>[];
      final pending = Completer<String?>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'chooseInvoice') return pending.future;
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      void guard() {
        if (!allowed) {
          throw const ApiException(
            kind: ApiErrorKind.forbidden,
            message: 'Account changed',
          );
        }
      }

      final bytes = Uint8List.fromList('%PDF-fixture'.codeUnits);
      final result = saveAndroidInvoice(
        bytes,
        'invoice.pdf',
        accessGuard: guard,
      );
      final rejected = expectLater(result, throwsA(isA<ApiException>()));
      await tester.pump();
      allowed = false;
      pending.complete('content://fixture/invoice');
      await tester.pump();
      await rejected;
      expect(calls.length, 1);
      expect((calls.single.arguments as Map).containsKey('bytes'), isFalse);
      allowed = true;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return call.method == 'chooseInvoice'
            ? 'content://fixture/invoice'
            : true;
      });
      expect(
        await saveAndroidInvoice(bytes, 'invoice.pdf', accessGuard: guard),
        'Invoice saved to the selected document.',
      );
      expect(calls.last.method, 'writeInvoice');
      expect((calls.last.arguments as Map)['bytes'], bytes);
    },
  );
  test('daily boost analytics require a confirmed owned boost before fetching rows', () async {
    var allowed = false;
    final h = Harness(
      call.Wire((r) {
        if (r.uri.path.endsWith('/analytics/daily')) {
          return boost.ok([
            {'date': '2026-11-04', ...boost.stats()},
          ]);
        }
        return allowed
            ? boost.ok(boost.monitor())
            : const TransportResponse(statusCode: 403, body: 'Not owned');
      }),
    );
    await expectLater(h.boosts.boostDaily(9), throwsA(isA<ApiException>()));
    expect(h.wire.requests.length, 1);
    expect(h.wire.requests.single.uri.path, '/api/v1/lawyer/boosts/9');
    allowed = true;
    expect((await h.boosts.boostDaily(9)).single.fields['impressions'], 17);
    expect(
      h.wire.requests.last.uri.path,
      '/api/v1/lawyer/boosts/9/analytics/daily',
    );
  });
}
