import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/lawyer/data/lawyer_repository.dart';
import 'package:attorlink_flutter/features/boosts/data/boost_repository.dart';
import 'package:attorlink_flutter/features/boosts/domain/boost_models.dart';
import 'package:attorlink_flutter/features/boosts/presentation/boost_screens.dart';

// Fixtures exercise contracts only; no live payment or activation is simulated.
const user = AuthUser(
  id: 7,
  email: 'fixture@example.invalid',
  role: UserRole.lawyer,
  status: UserStatus.active,
);
const demo =
    'https://merchantdemo.sandbox.bka.sh/tokenized-checkout/version/v2';
Map<String, Object?> plan() => {
  'id': 2,
  'name': 'Fixture plan',
  'description': 'Description',
  'durationDays': 7,
  'price': 250.50,
  'currency': 'BDT',
};
Map<String, Object?> purchase() => {
  'boostId': 9,
  'paymentId': 11,
  'planName': 'Fixture plan',
  'durationDays': 7,
  'amount': 250.50,
  'currency': 'BDT',
  'boostStatus': 'PENDING_PAYMENT',
  'paymentStatus': 'INITIATED',
  'createdAt': '2026-11-04T12:00:00',
};
Map<String, Object?> monitor() => {
  ...purchase(),
  'lawyerId': 7,
  'invoiceId': 15,
  'invoiceNumber': 'INV-FIXTURE',
  'invoiceStatus': 'ISSUED',
};
Map<String, Object?> invoice() => {
  'id': 15,
  'boostId': 9,
  'paymentId': 11,
  'invoiceNumber': 'INV-FIXTURE',
  'status': 'ISSUED',
  'amount': 250.50,
  'currency': 'BDT',
  'pdfUrl': 'https://files.example.invalid/invoice.pdf',
};
Map<String, Object?> stats() => {
  'impressions': 17,
  'uniqueReach': 9,
  'profileVisits': 4,
  'likes': 2,
  'comments': 1,
  'shares': 0,
  'engagementRate': 17.647,
};
Map<String, Object?> handoff() => {
  'boostId': 9,
  'paymentId': 11,
  'planName': 'Fixture plan',
  'amount': 250.50,
  'currency': 'BDT',
  'sandboxDemoUrl': demo,
  'paymentStatus': 'INITIATED',
  'paymentNote': 'Sandbox demo only. Does not mark payment completed.',
  'createdAt': '2026-11-04T12:00:00',
};
Map<String, Object?> profile([String status = 'VERIFIED']) => {
  'id': 3,
  'userId': 7,
  'profileStatus': status,
};
Map<String, Object?> page(
  List<Object?> rows, {
  int number = 0,
  int totalPages = 1,
}) => {
  'content': rows,
  'page': number,
  'size': 20,
  'totalElements': rows.length,
  'totalPages': totalPages,
};
TransportResponse ok(Object? data) => TransportResponse(
  statusCode: 200,
  body: jsonEncode({'success': true, 'message': 'Success', 'data': data}),
);

class Wire implements HttpTransport {
  Wire(this.handler);
  final FutureOr<TransportResponse> Function(TransportRequest) handler;
  final requests = <TransportRequest>[];
  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    return handler(request);
  }

  @override
  void close() {}
}

ApiClient api(Wire wire) => ApiClient(
  config: ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1/')),
  transport: wire,
  accessTokenProvider: () => 'fixture-access',
);
BoostRepository repository(Wire wire, {AuthUser? Function()? currentUser}) =>
    BoostRepository(
      LawyerRepository(
        api(wire),
        ownerId: 7,
        currentUser: currentUser ?? () => user,
      ),
    );

void main() {
  test(
    '7B plans, verified purchase and sandbox handoff use exact contracts',
    () async {
      final wire = Wire((r) {
        if (r.uri.path.endsWith('/boost-plans')) return ok([plan()]);
        if (r.uri.path.endsWith('/profile')) return ok(profile());
        if (r.uri.path.endsWith('/sandbox-checkout')) return ok(handoff());
        return ok(purchase());
      });
      final repo = repository(wire);
      final plans = await repo.plans();
      expect(plans.single.text('price'), '250.5');
      final result = await repo.purchase(plans.single.id);
      expect(result.text('boostStatus'), 'PENDING_PAYMENT');
      expect(wire.requests.last.method, 'POST');
      expect(jsonDecode(wire.requests.last.body!), {'planId': 2});
      final checkout = await repo.checkout(result.id);
      expect(checkout.text('sandboxDemoUrl'), demo);
      expect(checkout.text('paymentStatus'), 'INITIATED');
      expect(wire.requests.last.method, 'GET');
      expect(
        wire.requests.last.uri.path,
        '/api/v1/lawyer/boosts/9/sandbox-checkout',
      );
      expect(
        wire.requests.every(
          (r) => r.headers['Authorization'] == 'Bearer fixture-access',
        ),
        isTrue,
      );
      expect(() => checkoutUri('javascript:alert(1)'), throwsFormatException);
      expect(
        () => checkoutUri('https://secret@example.invalid'),
        throwsFormatException,
      );
    },
  );

  test('7B verification, ownership, conflict and uncertain purchase failures never auto-replay', () async {
    var verified = false;
    var status = 409;
    final wire = Wire(
      (r) => r.uri.path.endsWith('/profile')
          ? ok(profile(verified ? 'VERIFIED' : 'DRAFT'))
          : TransportResponse(
              statusCode: status,
              body: jsonEncode({
                'success': false,
                'message': 'Pending purchase already exists',
                'data': null,
              }),
            ),
    );
    final repo = repository(wire);
    await expectLater(
      repo.purchase(2),
      throwsA(
        isA<ApiException>().having(
          (e) => e.kind,
          'kind',
          ApiErrorKind.forbidden,
        ),
      ),
    );
    expect(wire.requests.where((r) => r.method == 'POST'), isEmpty);
    verified = true;
    await expectLater(
      repo.purchase(2),
      throwsA(
        isA<ApiException>().having(
          (e) => e.kind,
          'kind',
          ApiErrorKind.conflict,
        ),
      ),
    );
    expect(wire.requests.where((r) => r.method == 'POST').length, 1);
    status = 503;
    await expectLater(repo.purchase(2), throwsA(isA<ApiException>()));
    expect(wire.requests.where((r) => r.method == 'POST').length, 2);
    final client = repository(
      wire,
      currentUser: () => const AuthUser(
        id: 7,
        email: 'client@example.invalid',
        role: UserRole.client,
        status: UserStatus.active,
      ),
    );
    await expectLater(client.plans(), throwsA(isA<ApiException>()));
    final ownerMismatch = repository(
      Wire((_) => ok({...monitor(), 'lawyerId': 99})),
    );
    await expectLater(ownerMismatch.detail(9), throwsA(isA<ApiException>()));
    expect(
      () => BoostData.fromJson({
        ...purchase(),
        'paymentStatus': 'PAID',
      }, BoostDto.purchase),
      throwsFormatException,
    );
  });

  test('7B paginated history/activity, invoices and actual analytics preserve backend data', () async {
    final wire = Wire((r) {
      final p = r.uri.path;
      if (p.endsWith('/activities')) {
        return ok(
          page(
            [
              {
                'id': 4,
                'activityType': 'PAYMENT_INITIATED',
                'description': 'Recorded',
                'createdAt': '2026-11-04T12:00:00',
              },
            ],
            number: 1,
            totalPages: 2,
          ),
        );
      }
      if (p.endsWith('/invoices')) return ok([invoice()]);
      if (p.endsWith('/invoices/15')) return ok(invoice());
      if (p.endsWith('/analytics/daily')) {
        return ok(
          p.contains('/9/')
              ? [
                  {'date': '2026-11-04', ...stats()},
                ]
              : page([
                  {'date': '2026-11-04', ...stats()},
                ]),
        );
      }
      if (p.endsWith('/analytics') || p.endsWith('/analytics/summary')) {
        return ok({
          ...stats(),
          'boostId': p.contains('/9/') ? 9 : null,
          'packageName': 'Fixture',
          'status': p.contains('/9/') ? 'ACTIVE' : null,
        });
      }
      if (p.endsWith('/boosts/9')) return ok(monitor());
      return ok(page([monitor()]));
    });
    final repo = repository(wire);
    expect((await repo.history()).content.single.id, 9);
    expect(wire.requests.last.uri.queryParameters, {'page': '0', 'size': '20'});
    expect((await repo.detail(9)).text('paymentStatus'), 'INITIATED');
    expect((await repo.activities(9, page: 1)).page, 1);
    expect(wire.requests.last.uri.queryParameters['page'], '1');
    expect((await repo.invoices()).single.id, 15);
    expect((await repo.invoice(15)).text('status'), 'ISSUED');
    final summary = await repo.summary(
      boostId: 9,
      from: '2026-11-01T00:00:00.123456789',
      to: '2026-11-05T00:00',
    );
    expect(summary.fields['impressions'], 17);
    expect(
      wire.requests.last.uri.queryParameters['from'],
      '2026-11-01T00:00:00.123456789',
    );
    expect(wire.requests.last.uri.queryParameters['to'], '2026-11-05T00:00:00');
    await repo.summary();
    expect(
      wire.requests.last.uri.path,
      '/api/v1/lawyer/boosts/analytics/summary',
    );
    expect((await repo.daily()).content.single.fields['uniqueReach'], 9);
    expect((await repo.boostDaily(9)).single.fields['engagementRate'], 17.647);
    expect(
      () => repo.summary(from: '2026-11-05T00:00', to: '2026-11-01T00:00'),
      throwsFormatException,
    );
  });

  test('7B authenticated PDF bytes survive refresh; invalid PDFs and account changes are rejected', () async {
    var token = 'old', refreshes = 0;
    final pdf = Uint8List.fromList([
      ...ascii.encode('%PDF-1.7\n'),
      0,
      255,
      128,
    ]);
    final wire = Wire(
      (r) => r.headers['Authorization'] == 'Bearer old'
          ? TransportResponse(statusCode: 401, body: 'Unauthorized')
          : TransportResponse(statusCode: 200, body: '', bodyBytes: pdf),
    );
    final client = ApiClient(
      config: ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1/')),
      transport: wire,
      accessTokenProvider: () => token,
      recoverAuthentication: (_) async {
        token = 'fresh';
        refreshes++;
        return true;
      },
    );
    final repo = BoostRepository(
      LawyerRepository(client, ownerId: 7, currentUser: () => user),
    );
    expect(await repo.invoicePdf(15), orderedEquals(pdf));
    expect(refreshes, 1);
    expect(wire.requests.length, 2);
    expect(
      wire.requests.every(
        (r) =>
            r.receiveBytes &&
            r.headers['Accept'] == 'application/pdf' &&
            !r.uri.hasQuery,
      ),
      isTrue,
    );
    final invalid = repository(
      Wire(
        (_) => TransportResponse(
          statusCode: 200,
          body: '',
          bodyBytes: Uint8List.fromList(ascii.encode('<html>')),
        ),
      ),
    );
    await expectLater(invalid.invoicePdf(15), throwsA(isA<ApiException>()));
    AuthUser? current = user;
    final delayed = Completer<TransportResponse>();
    final guarded = repository(
      Wire((_) => delayed.future),
      currentUser: () => current,
    );
    final result = guarded.invoicePdf(15);
    await Future<void>.delayed(Duration.zero);
    current = null;
    delayed.complete(
      TransportResponse(statusCode: 200, body: '', bodyBytes: pdf),
    );
    await expectLater(result, throwsA(isA<ApiException>()));
  });

  testWidgets(
    '7B purchase review and sandbox opening never complete payment locally',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 1900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var completed = false;
      String? opened;
      final wire = Wire((r) {
        if (r.uri.path.endsWith('/profile')) return ok(profile());
        if (r.uri.path.endsWith('/purchase')) return ok(purchase());
        if (r.uri.path.endsWith('/sandbox-checkout')) return ok(handoff());
        return ok({
          ...monitor(),
          'boostStatus': completed ? 'ACTIVE' : 'PENDING_PAYMENT',
          'paymentStatus': completed ? 'COMPLETED' : 'INITIATED',
        });
      });
      final repo = repository(wire);
      await tester.pumpWidget(
        MaterialApp(
          home: BoostPlanReview(
            repository: repo,
            plan: BoostData.fromJson(plan(), BoostDto.plan),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Initiate purchase'));
      await tester.pumpAndSettle();
      expect(find.text('boostStatus: PENDING_PAYMENT'), findsOneWidget);
      expect(wire.requests.where((r) => r.method == 'POST').length, 1);
      await tester.pumpWidget(
        MaterialApp(
          home: BoostDetail(
            repository: repo,
            id: 9,
            checkoutOpener: (url) async {
              opened = url;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get sandbox checkout'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Open sandbox demo'));
      await tester.tap(find.text('Open sandbox demo'));
      await tester.pumpAndSettle();
      expect(opened, demo);
      expect(find.text('boostStatus: PENDING_PAYMENT'), findsOneWidget);
      expect(find.text('paymentStatus: COMPLETED'), findsNothing);
      expect(wire.requests.where((r) => r.method == 'POST').length, 1);
      completed = true; // A later authoritative backend fixture, not a checkout callback.
      await tester.tap(find.byTooltip('Refresh backend status'));
      await tester.pumpAndSettle();
      expect(find.text('boostStatus: ACTIVE'), findsOneWidget);
      expect(find.text('paymentStatus: COMPLETED'), findsOneWidget);
      expect(find.text('Open sandbox demo'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
