import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attorlink_flutter/features/lawyer/qualifications/domain/qualification_schema.dart';
import 'package:attorlink_flutter/features/lawyer/qualifications/presentation/qualification_editor.dart';
import 'package:attorlink_flutter/features/lawyer/qualifications/presentation/qualifications_hub.dart';

import 'support/qualification_contracts.dart';

void main() {
  testWidgets('education requires degree before sending a create request', (
    tester,
  ) async {
    final fixture = QualificationTestFixture(QualificationResource.education);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QualificationEditor(
            repository: fixture.repository,
            resource: QualificationResource.education,
            onSaved: (_) {},
            onReload: () {},
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Save record'));
    await tester.tap(find.text('Save record'));
    await tester.pumpAndSettle();
    expect(find.text('Degree is required.'), findsOneWidget);
    expect(fixture.transport.requests, isEmpty);
  });

  testWidgets(
    'High Court detail offers edits and documents without whole-record deletion',
    (tester) async {
      final fixture = QualificationTestFixture(QualificationResource.highCourt);
      addTearDown(fixture.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QualificationsHub(repository: fixture.repository),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('HC-1'));
      await tester.pumpAndSettle();
      expect(find.text('Edit record'), findsOneWidget);
      expect(find.text('Manage documents'), findsOneWidget);
      expect(find.text('Delete record'), findsNothing);
      expect(
        fixture.transport.requests.every(
          (r) => r.uri.path == '/api/v1/lawyer/high-court',
        ),
        true,
      );
    },
  );

  testWidgets(
    'empty registration uses setup action and never fabricates a saved record',
    (tester) async {
      final fixture = QualificationTestFixture(QualificationResource.highCourt);
      fixture.record = null;
      addTearDown(fixture.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QualificationsHub(repository: fixture.repository),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No records saved yet.'), findsOneWidget);
      await tester.tap(find.text('Set up registration'));
      await tester.pumpAndSettle();
      expect(find.text('Save record'), findsOneWidget);
      expect(fixture.transport.requests.any((r) => r.method != 'GET'), false);
    },
  );
}
