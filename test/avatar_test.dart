import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:college_app/core/widgets/avatar.dart';

void main() {
  group('AppAvatar', () {
    testWidgets('shows the first letter of the name when there is no photo', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppAvatar(photoUrl: null, name: 'Deepak', radius: 20),
        ),
      );

      expect(find.text('D'), findsOneWidget);
    });

    testWidgets('falls back to "?" for an empty name', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppAvatar(photoUrl: null, name: '', radius: 20),
        ),
      );

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('uppercases a lowercase name initial', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppAvatar(photoUrl: null, name: 'anita', radius: 20),
        ),
      );

      expect(find.text('A'), findsOneWidget);
    });
  });
}
