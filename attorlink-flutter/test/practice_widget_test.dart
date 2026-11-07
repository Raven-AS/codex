import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attorlink_flutter/features/lawyer/practice/domain/practice_models.dart';
import 'package:attorlink_flutter/features/lawyer/practice/domain/practice_schema.dart';
import 'package:attorlink_flutter/features/lawyer/practice/presentation/availability_editor.dart';
import 'package:attorlink_flutter/features/lawyer/practice/presentation/practice_editor.dart';

import 'support/practice_contracts.dart';

void main() {
  testWidgets('legal service required fields fail before POST', (tester) async {
    final fixture = PracticeTestFixture(PracticeResource.services);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeEditor(
            repository: fixture.repository,
            resource: PracticeResource.services,
            onSaved: (_) {},
            onReload: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save practice record'));
    await tester.tap(find.text('Save practice record'));
    await tester.pumpAndSettle();
    expect(find.text('Service name is required.'), findsOneWidget);
    expect(find.text('Consultation type is required.'), findsOneWidget);
    expect(fixture.transport.requests, isEmpty);
  });

  testWidgets(
    'editing preserves a saved reference missing from active catalog',
    (tester) async {
      final fixture = PracticeTestFixture(PracticeResource.specializations);
      addTearDown(fixture.dispose);
      fixture.records.single['practiceAreaId'] = 999;
      fixture.records.single['practiceAreaName'] = 'Existing area';
      final initial = PracticeRecord.fromJson(
        fixture.resource,
        fixture.records.single,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PracticeEditor(
              repository: fixture.repository,
              resource: fixture.resource,
              initial: initial,
              onSaved: (_) {},
              onReload: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<int>>(
              find.byType(DropdownButtonFormField<int>),
            )
            .initialValue,
        999,
      );
      await tester.ensureVisible(find.text('Save practice record'));
      await tester.tap(find.text('Save practice record'));
      await tester.pumpAndSettle();
      final put = fixture.transport.requests.last;
      expect(put.method, 'PUT');
      expect((jsonDecode(put.body!) as Map)['practiceAreaId'], 999);
    },
  );

  testWidgets(
    'unavailable saved slots are not promoted and clear uses empty bulk PUT',
    (tester) async {
      final fixture = PracticeTestFixture(PracticeResource.languages);
      fixture.slots = [availabilityJson(available: false)];
      addTearDown(fixture.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AvailabilityEditor(repository: fixture.repository),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Monday'),
            )
            .value,
        false,
      );
      expect(find.byType(TextFormField), findsNothing);
      await tester.ensureVisible(find.text('Save whole week'));
      await tester.tap(find.text('Save whole week'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear saved week'));
      await tester.pumpAndSettle();
      final request = fixture.transport.requests.last;
      expect(request.method, 'PUT');
      expect((jsonDecode(request.body!) as Map)['slots'], isEmpty);
      expect(find.text('Weekly availability saved.'), findsOneWidget);
    },
  );

  testWidgets('weekly editor retains multiple ranges on the same day', (
    tester,
  ) async {
    final fixture = PracticeTestFixture(PracticeResource.languages);
    fixture.slots = [
      availabilityJson(),
      availabilityJson(id: 2, start: '13:00:01.123456789', end: '17:00:00'),
    ];
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AvailabilityEditor(repository: fixture.repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(4));
    await tester.ensureVisible(find.text('Add time range'));
    await tester.tap(find.text('Add time range'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(6));
    expect(fixture.transport.requests.where((r) => r.method != 'GET'), isEmpty);
  });
}
