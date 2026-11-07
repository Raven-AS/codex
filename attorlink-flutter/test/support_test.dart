import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/api_exception.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/auth/domain/auth_models.dart';
import 'package:attorlink_flutter/features/settings/data/settings_repository.dart';
import 'package:attorlink_flutter/features/settings/presentation/settings_screens.dart';
import 'package:attorlink_flutter/features/support/domain/support_ticket.dart';
import 'package:attorlink_flutter/features/support/data/support_repository.dart';
import 'package:attorlink_flutter/features/support/presentation/support_screens.dart';

// Fixtures only: no live ticket or email operation is simulated in production.
const user = AuthUser(
  id: 7,
  email: 'fixture@example.invalid',
  role: UserRole.client,
  status: UserStatus.active,
);
Map<String, Object?> ticket({
  int id = 5,
  String status = 'OPEN',
  String category = 'TECHNICAL',
}) => {
  'id': id,
  'referenceNumber': 'SUP-FIXTURE-$id',
  'subject': 'A problem',
  'message': 'A detailed issue description',
  'category': category,
  'status': status,
  'createdAt': '2026-11-05T10:00:00.123456789',
  'updatedAt': '2026-11-05T10:01:00',
};
Map<String, Object?> page(
  List<Object?> rows, {
  int number = 0,
  int pages = 1,
}) => {
  'content': rows,
  'page': number,
  'size': 10,
  'totalElements': rows.length,
  'totalPages': pages,
};
TransportResponse ok(Object? data, {int status = 200}) => TransportResponse(
  statusCode: status,
  body: jsonEncode({'success': true, 'message': 'Success', 'data': data}),
);

class Wire implements HttpTransport {
  Wire(this.handler);
  final FutureOr<TransportResponse> Function(TransportRequest) handler;
  final requests = <TransportRequest>[];
  @override
  Future<TransportResponse> send(TransportRequest r) async {
    requests.add(r);
    return handler(r);
  }

  @override
  void close() {}
}

ApiClient api(Wire wire) => ApiClient(
  config: ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1/')),
  transport: wire,
  accessTokenProvider: () => 'fixture-access',
);
SupportRepository repository(
  Wire wire, {
  AuthUser? Function()? current,
  Stream<Object?>? changes,
}) => SupportRepository(
  api(wire),
  ownerId: 7,
  currentUser: current ?? () => user,
  accessChanges: changes,
);
void main() {
  test('8B exact create/list/detail contracts preserve status, references and pagination', () async {
    final wire = Wire((r) {
      if (r.method == 'POST') {
        return ok(ticket(), status: 201);
      }
      if (r.uri.path.endsWith('/tickets/5')) {
        return ok(ticket(status: 'RESOLVED'));
      }
      return ok(
        page(
          [ticket()],
          number: int.parse(r.uri.queryParameters['page']!),
          pages: 2,
        ),
      );
    });
    final repo = repository(wire);
    final created = await repo.create(
      subject: '  A problem  ',
      message: '  A detailed issue description  ',
      category: 'TECHNICAL',
    );
    expect(created.status, 'OPEN');
    expect(created.reference, 'SUP-FIXTURE-5');
    expect(jsonDecode(wire.requests.last.body!), {
      'subject': 'A problem',
      'message': 'A detailed issue description',
      'category': 'TECHNICAL',
    });
    expect(wire.requests.last.uri.path, '/api/v1/support/tickets');
    final first = await repo.list();
    expect(first.hasNext, isTrue);
    expect(wire.requests.last.uri.queryParameters, {'page': '0', 'size': '10'});
    final second = await repo.list(page: 1);
    expect(second.page, 1);
    expect(second.hasNext, isFalse);
    expect((await repo.get(5)).status, 'RESOLVED');
    expect(wire.requests.last.uri.path, '/api/v1/support/tickets/5');
    expect(
      wire.requests.every(
        (r) => r.headers['Authorization'] == 'Bearer fixture-access',
      ),
      isTrue,
    );
    expect(created.createdAt, '2026-11-05T10:00:00.123456789');
  });
  test(
    '8B validation matches trimmed limits and only backend categories/statuses',
    () async {
      final wire = Wire((_) => ok(ticket()));
      final repo = repository(wire);
      for (final values in [
        ('', '0123456789'),
        ('x' * 161, '0123456789'),
        ('ok', '  short  '),
        ('ok', 'x' * 4001),
      ]) {
        await expectLater(
          repo.create(subject: values.$1, message: values.$2),
          throwsA(isA<ApiException>()),
        );
      }
      await expectLater(
        repo.create(
          subject: 'Valid',
          message: '0123456789',
          category: 'URGENT',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(wire.requests, isEmpty);
      expect(ticketSubjectError('x' * 160), isNull);
      expect(ticketMessageError('x' * 4000), isNull);
      await repo.create(subject: 'Valid', message: '0123456789');
      expect(jsonDecode(wire.requests.single.body!)['category'], 'GENERAL');
      for (final category in ticketCategories) {
        expect(
          SupportTicket.fromJson(ticket(category: category)).category,
          category,
        );
      }
      for (final status in ticketStatuses) {
        expect(SupportTicket.fromJson(ticket(status: status)).status, status);
      }
      expect(
        () => SupportTicket.fromJson(ticket(status: 'PENDING')),
        throwsFormatException,
      );
      expect(
        () => SupportTicket.fromJson(ticket(category: 'OTHER')),
        throwsFormatException,
      );
    },
  );
  test('8B access guards reject cross-account responses, wrong IDs and forbidden retrieval', () async {
    AuthUser? current = user;
    final pending = Completer<TransportResponse>();
    final wire = Wire((_) => pending.future);
    final repo = repository(wire, current: () => current);
    final request = repo.list();
    await Future<void>.delayed(Duration.zero);
    current = null;
    pending.complete(ok(page([ticket()])));
    await expectLater(request, throwsA(isA<ApiException>()));
    await expectLater(
      repo.create(subject: 'Valid', message: '0123456789'),
      throwsA(isA<ApiException>()),
    );
    expect(wire.requests.length, 1);
    final wrong = repository(Wire((_) => ok(ticket(id: 6))));
    await expectLater(wrong.get(5), throwsA(isA<ApiException>()));
    final forbidden = repository(
      Wire((_) => const TransportResponse(statusCode: 403, body: 'Forbidden')),
    );
    await expectLater(
      forbidden.get(5),
      throwsA(
        isA<ApiException>().having(
          (e) => e.kind,
          'kind',
          ApiErrorKind.forbidden,
        ),
      ),
    );
  });
  testWidgets(
    '8B uncertain submission retains draft, blocks replay and reacts to session loss',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1300);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AuthUser? current = user;
      final changes = StreamController<Object?>.broadcast();
      addTearDown(changes.close);
      final wire = Wire(
        (_) => const TransportResponse(statusCode: 503, body: 'Unavailable'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SupportTicketForm(
            repository: repository(
              wire,
              current: () => current,
              changes: changes.stream,
            ),
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Subject'),
        'A problem',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Message'),
        'A detailed issue description',
      );
      await tester.tap(find.text('Submit ticket'));
      await tester.pumpAndSettle();
      expect(find.text('A detailed issue description'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Submit ticket'),
            )
            .onPressed,
        isNull,
      );
      expect(wire.requests.length, 1);
      current = null;
      changes.add(null);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('same active client or lawyer'),
        findsOneWidget,
      );
      expect(find.text('Submit ticket'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    '8B settings navigation creates a ticket then refreshes authoritative detail status',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1400);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var created = false, resolved = false;
      final wire = Wire((r) {
        if (r.method == 'POST') {
          created = true;
          return ok(ticket(), status: 201);
        }
        if (r.uri.path.endsWith('/tickets/5')) {
          return ok(ticket(status: resolved ? 'RESOLVED' : 'OPEN'));
        }
        return ok(page(created ? [ticket()] : []));
      });
      final settings = SettingsRepository(
        api(wire),
        ownerId: 7,
        currentUser: () => user,
        invalidateSession: (_) async {},
        recheckSession: () async {},
      );
      await tester.pumpWidget(
        MaterialApp(home: SettingsHome(repository: settings)),
      );
      await tester.tap(find.text('Support tickets'));
      await tester.pumpAndSettle();
      expect(find.text('No support tickets yet.'), findsOneWidget);
      await tester.tap(find.text('Create support ticket'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit ticket'));
      await tester.pumpAndSettle();
      expect(find.text('Subject is required.'), findsOneWidget);
      expect(wire.requests.where((r) => r.method == 'POST'), isEmpty);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Subject'),
        'A problem',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Message'),
        'A detailed issue description',
      );
      await tester.tap(find.text('Submit ticket'));
      await tester.pumpAndSettle();
      expect(find.text('Backend status: OPEN'), findsOneWidget);
      resolved = true;
      await tester.tap(find.byTooltip('Refresh ticket status'));
      await tester.pumpAndSettle();
      expect(find.text('Backend status: RESOLVED'), findsOneWidget);
      expect(wire.requests.where((r) => r.method == 'POST').length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
