import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulgapp_mobile/client_preferences.dart';
import 'package:pulgapp_mobile/controller_profile.dart';
import 'package:pulgapp_mobile/main.dart';

Future<ClientPreferences> _loadPreferences(
  WidgetTester tester, [
  Map<String, String> values = const {},
]) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('pulgapp/preferences'),
    (call) async => call.method == 'getAll' ? values : null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('pulgapp/preferences'),
      null,
    ),
  );
  return ClientPreferences.load();
}

Future<void> _showConnectPage(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
  Map<String, String> values = const {},
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final preferences = await _loadPreferences(tester, values);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: ConnectPage(preferences: preferences),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'invalid endpoint and PIN identify both fields before connecting',
    (tester) async {
      await _showConnectPage(tester, size: const Size(640, 320));
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '192.168.1.3:26760');
      await tester.enterText(fields.at(1), '12');
      await tester.tap(find.text('CONNECT'));
      await tester.pump();

      expect(find.text('Enter an IPv4 address or hostname.'), findsOneWidget);
      expect(find.text('Enter the six-digit PIN.'), findsOneWidget);
      expect(find.textContaining('ArgumentError'), findsNothing);
    },
  );

  testWidgets('landscape login uses the available width without overflow', (
    tester,
  ) async {
    await _showConnectPage(tester, size: const Size(640, 320), textScale: 1.5);
    final fields = find.byType(TextField);
    final endpoint = tester.getRect(fields.at(0));
    final pin = tester.getRect(fields.at(1));

    expect((endpoint.top - pin.top).abs(), lessThan(2));
    expect(endpoint.width, greaterThanOrEqualTo(250));
    expect(pin.width, greaterThanOrEqualTo(250));
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait login stacks fields without overflow', (tester) async {
    await _showConnectPage(tester, size: const Size(360, 640), textScale: 1.5);
    final fields = find.byType(TextField);
    expect(
      tester.getTopLeft(fields.at(1)).dy,
      greaterThan(tester.getBottomLeft(fields.at(0)).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected button mapping is visible before connecting', (
    tester,
  ) async {
    final mapping = ControllerButtonMapping.identity.remap('A', 'b');
    final profiles = ControllerProfileLibrary.initial()
        .create(id: 'custom', name: 'Custom')
        .updateButtonMapping('custom', mapping)
        .select('custom');
    await _showConnectPage(
      tester,
      size: const Size(640, 320),
      values: {'controller-profiles-v1': profiles.encode()},
    );

    expect(find.textContaining('A → B'), findsOneWidget);
    expect(find.textContaining('B → A'), findsOneWidget);
  });

  testWidgets('PIN visibility can be toggled', (tester) async {
    await _showConnectPage(tester, size: const Size(640, 320));
    final pinFieldFinder = find.byKey(const ValueKey('pin-field'));
    var pinField = tester.widget<TextField>(pinFieldFinder);
    expect(pinField.obscureText, isFalse);

    await tester.tap(find.byKey(const ValueKey('toggle-pin-visibility')));
    await tester.pump();

    pinField = tester.widget<TextField>(pinFieldFinder);
    expect(pinField.obscureText, isTrue);
  });

  testWidgets('pre-populates endpoint and PIN from preferences', (tester) async {
    await _showConnectPage(
      tester,
      size: const Size(640, 320),
      values: {
        'last-endpoint': '192.168.1.50',
        'last-pin': '654321',
      },
    );
    expect(find.text('192.168.1.50'), findsOneWidget);
    expect(find.text('654321'), findsOneWidget);
  });
}
