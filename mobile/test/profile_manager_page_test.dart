import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulgapp_mobile/client_preferences.dart';
import 'package:pulgapp_mobile/controller/profile_manager_page.dart';

void main() {
  testWidgets('creates a selected profile and persists it locally', (tester) async {
    final storage = <String, String>{};
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('pulgapp/preferences'),
      (call) async {
        if (call.method == 'getAll') return storage;
        if (call.method == 'setString') {
          final arguments = call.arguments as Map<dynamic, dynamic>;
          storage[arguments['key'] as String] = arguments['value'] as String;
          return null;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('pulgapp/preferences'), null));

    final preferences = await ClientPreferences.load();
    await tester.pumpWidget(MaterialApp(
      home: ProfileManagerPage(
        preferences: preferences,
        initialProfiles: preferences.controllerProfiles,
      ),
    ));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Friday party');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Friday party'), findsOneWidget);
    expect(preferences.controllerProfiles.selected.name, 'Friday party');
    expect(storage['controller-profiles-v1'], isNotNull);
  });
}
