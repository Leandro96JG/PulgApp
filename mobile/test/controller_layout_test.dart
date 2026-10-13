import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulgapp_mobile/controller_connection.dart';
import 'package:pulgapp_mobile/main.dart';
import 'package:pulgapp_mobile/controller/test_pad_page.dart';
import 'package:pulgapp_mobile/controller/touch_controller.dart';
import 'package:pulgapp_mobile/controller_profile.dart';
import 'package:pulgapp_mobile/gamepad_input_model.dart';
import 'package:pulgapp_mobile/gamepad_state.dart';

const _ids = [
  'LT',
  'LB',
  'RB',
  'RT',
  'LS',
  'RS',
  'D-pad',
  'A',
  'B',
  'X',
  'Y',
  'Back',
  'Guide',
  'Start',
  'L3',
  'R3',
];
Finder control(String id) => find.byKey(ValueKey('control-$id'));

Future<void> showController(
  WidgetTester tester,
  GamepadInputModel model, {
  Size size = const Size(740, 360),
  double scale = 1,
  bool enabled = true,
  ControllerType controllerType = ControllerType.x360,
  ControllerStickSettings stickSettings = ControllerStickSettings.defaults,
  ControllerButtonMapping buttonMapping = ControllerButtonMapping.identity,
  ControllerLayoutSettings layoutSettings = ControllerLayoutSettings.defaults,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: SafeArea(
            child: RepaintBoundary(
              key: const ValueKey('preview'),
              child: TouchController(
                model: model,
                controllerType: controllerType,
                enabled: enabled,
                status: 'Slot 1 | connected',
                stickSettings: stickSettings,
                buttonMapping: buttonMapping,
                layoutSettings: layoutSettings,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    try {
      // Use the SDK's Android fonts if available, falling back gracefully in CI environments.
      final configFile = File('.dart_tool/package_config.json').absolute;
      if (!await configFile.exists()) return;
      final config =
          jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
      final packages = config['packages'] as List?;
      if (packages == null) return;
      final flutter = packages.cast<Map<String, dynamic>>().firstWhere(
        (p) => p['name'] == 'flutter',
        orElse: () => <String, dynamic>{},
      );
      final rootUri = flutter['rootUri'] as String?;
      if (rootUri == null) return;
      final fonts = Directory.fromUri(
        configFile.uri.resolve(rootUri),
      ).uri.resolve('../../bin/cache/artifacts/material_fonts/');
      for (final font in [
        ('Roboto', 'roboto-regular.ttf'),
        ('MaterialIcons', 'materialicons-regular.otf'),
      ]) {
        final fontFile = File.fromUri(fonts.resolve(font.$2));
        if (await fontFile.exists()) {
          final loader = FontLoader(font.$1)
            ..addFont(
              fontFile.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
            );
          await loader.load();
        }
      }
    } catch (_) {
      // Ignore font loading errors in headless CI environments where SDK artifacts are not cached.
    }
  });
  testWidgets('action touch targets never overlap', (tester) async {
    tester.view.physicalSize = const Size(740, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('pulgapp/wakelock'),
      (_) async => null,
    );
    final connection = ControllerConnection(
      clientId: 'layout-test',
      clientName: 'Test',
      saveEndpoint: (_) async {},
    );
    await tester.pumpWidget(
      MaterialApp(home: ControllerPage(connection: connection)),
    );
    final targets = ['A', 'B', 'X', 'Y']
        .map(
          (label) => tester.getRect(
            find
                .ancestor(of: find.text(label), matching: find.byType(Listener))
                .first,
          ),
        )
        .toList();
    for (var i = 0; i < targets.length; i++) {
      for (var j = i + 1; j < targets.length; j++) {
        expect(
          targets[i].overlaps(targets[j]),
          isFalse,
          reason: 'Action touch areas $i and $j overlap',
        );
      }
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));
    await connection.dispose();
  });

  for (final size in const [
    Size(640, 320),
    Size(740, 360),
    Size(800, 360),
    Size(915, 412),
    Size(1280, 720),
  ]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('all targets fit and remain separate at $size text $scale', (
        tester,
      ) async {
        final model = GamepadInputModel();
        await showController(tester, model, size: size, scale: scale);
        expect(tester.takeException(), isNull);
        final safe = Rect.fromLTRB(24, 24, size.width - 24, size.height - 8);
        final rects = _ids.map((id) => tester.getRect(control(id))).toList();
        for (var i = 0; i < rects.length; i++) {
          expect(safe.contains(rects[i].topLeft), isTrue, reason: _ids[i]);
          expect(safe.contains(rects[i].bottomRight), isTrue, reason: _ids[i]);
          expect(
            rects[i].shortestSide,
            greaterThanOrEqualTo(48),
            reason: _ids[i],
          );
          for (var j = i + 1; j < rects.length; j++) {
            expect(
              rects[i].overlaps(rects[j].inflate(7.9)),
              isFalse,
              reason: '${_ids[i]} and ${_ids[j]} need an 8px gutter',
            );
          }
        }
        await tester.pumpWidget(const SizedBox());
        model.dispose();
      });
    }
  }

  testWidgets(
    'button corners are tappable and release/cancel clears every button',
    (tester) async {
      final model = GamepadInputModel();
      await showController(tester, model);
      for (final label in [
        'A',
        'B',
        'X',
        'Y',
        'LB',
        'RB',
        'L3',
        'R3',
        'Back',
        'Guide',
        'Start',
      ]) {
        final rect = tester.getRect(control(label));
        final gesture = await tester.startGesture(
          rect.topLeft + const Offset(2, 2),
        );
        expect(model.state.buttons, isNot(0), reason: label);
        await gesture.up();
        expect(model.state, GamepadState.neutral);
        final canceled = await tester.startGesture(
          rect.bottomRight - const Offset(2, 2),
        );
        await canceled.cancel();
        expect(model.state, GamepadState.neutral);
      }
    },
  );

  testWidgets(
    'remapped touch position sends and displays its assigned action',
    (tester) async {
      final model = GamepadInputModel();
      final mapping = ControllerButtonMapping.identity.remap('A', 'b');
      await showController(tester, model, buttonMapping: mapping);
      expect(
        find.descendant(of: control('A'), matching: find.text('B')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: control('A'), matching: find.text('A → B')),
        findsOneWidget,
      );
      final gesture = await tester.startGesture(tester.getCenter(control('A')));
      expect(model.state.buttons, GamepadButton.b);
      await gesture.up();
      expect(model.state, GamepadState.neutral);
    },
  );

  testWidgets('custom zone order and widths stay separate', (tester) async {
    final model = GamepadInputModel();
    final layout = ControllerLayoutSettings.defaults
        .reorder(3, 0)
        .resize('leftStick', 4);
    await showController(tester, model, layoutSettings: layout);
    expect(
      tester.getRect(control('A')).left,
      lessThan(tester.getRect(control('LS')).left),
    );
    final rects = [
      'A',
      'B',
      'X',
      'Y',
      'LS',
      'RS',
      'D-pad',
    ].map((id) => tester.getRect(control(id))).toList();
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        expect(rects[i].overlaps(rects[j]), isFalse);
      }
    }
  });

  testWidgets('both sticks, face buttons and shoulders work simultaneously', (
    tester,
  ) async {
    final model = GamepadInputModel();
    await showController(tester, model);
    final ls = await tester.startGesture(
      tester.getCenter(control('LS')),
      pointer: 1,
    );
    final rs = await tester.startGesture(
      tester.getCenter(control('RS')),
      pointer: 2,
    );
    await ls.moveBy(const Offset(-100, -100));
    await rs.moveBy(const Offset(100, 100));
    expect(model.state.leftX, lessThan(0));
    expect(model.state.leftY, greaterThan(0));
    expect(model.state.rightX, greaterThan(0));
    expect(model.state.rightY, lessThan(0));
    final radiusSquared =
        model.state.leftX * model.state.leftX +
        model.state.leftY * model.state.leftY;
    expect(radiusSquared, lessThanOrEqualTo(32768 * 32768));
    final held = <TestGesture>[];
    for (final label in ['A', 'B', 'LB', 'RB', 'LT', 'RT']) {
      held.add(
        await tester.startGesture(
          tester.getCenter(control(label)),
          pointer: 3 + held.length,
        ),
      );
    }
    expect(
      model.state.buttons,
      GamepadButton.a | GamepadButton.b | GamepadButton.lb | GamepadButton.rb,
    );
    expect(model.state.leftTrigger, closeTo(32768, 1));
    expect(model.state.rightTrigger, closeTo(32768, 1));
    await ls.cancel();
    expect(model.state.leftX, 0);
    expect(model.state.rightX, greaterThan(0));
    await rs.up();
    for (final gesture in held) {
      await gesture.cancel();
    }
    expect(model.state, GamepadState.neutral);
  });

  testWidgets('stick begins neutral anywhere; second finger cannot steal it', (
    tester,
  ) async {
    final model = GamepadInputModel();
    await showController(tester, model);
    final rect = tester.getRect(control('LS'));
    final first = await tester.startGesture(
      rect.topLeft + const Offset(4, 4),
      pointer: 1,
    );
    expect(model.state, GamepadState.neutral);
    await first.moveBy(const Offset(25, 0));
    final before = model.state;
    final second = await tester.startGesture(rect.center, pointer: 2);
    await second.moveBy(const Offset(0, 20));
    await second.up();
    expect(model.state, before);
    await first.cancel();
    expect(model.state, GamepadState.neutral);
  });

  testWidgets('D-pad slides through all directions, diagonals and neutral', (
    tester,
  ) async {
    final model = GamepadInputModel();
    await showController(tester, model);
    final center = tester.getCenter(control('D-pad'));
    final gesture = await tester.startGesture(center);
    const directions = [
      (Offset(0, -30), GamepadButton.dpadUp),
      (Offset(30, -30), GamepadButton.dpadUp | GamepadButton.dpadRight),
      (Offset(30, 0), GamepadButton.dpadRight),
      (Offset(30, 30), GamepadButton.dpadDown | GamepadButton.dpadRight),
      (Offset(0, 30), GamepadButton.dpadDown),
      (Offset(-30, 30), GamepadButton.dpadDown | GamepadButton.dpadLeft),
      (Offset(-30, 0), GamepadButton.dpadLeft),
      (Offset(-30, -30), GamepadButton.dpadUp | GamepadButton.dpadLeft),
      (Offset.zero, 0),
    ];
    for (final direction in directions) {
      await gesture.moveTo(center + direction.$1);
      expect(model.state.buttons, direction.$2);
    }
    await gesture.moveTo(center + const Offset(30, 0));
    await gesture.cancel();
    expect(model.state, GamepadState.neutral);
  });

  testWidgets('analog triggers cover min, midpoint, max and reset', (
    tester,
  ) async {
    final model = GamepadInputModel();
    await showController(tester, model);
    for (final id in ['LT', 'RT']) {
      final rect = tester.getRect(control(id));
      final gesture = await tester.startGesture(rect.center);
      int value() =>
          id == 'LT' ? model.state.leftTrigger : model.state.rightTrigger;
      expect(value(), closeTo(32768, 1));
      await gesture.moveTo(rect.bottomCenter);
      expect(value(), 0);
      await gesture.moveTo(rect.topCenter);
      expect(value(), 65535);
      await gesture.up();
      expect(value(), 0);
      final canceled = await tester.startGesture(rect.center);
      await canceled.cancel();
      expect(model.state, GamepadState.neutral);
    }
  });

  testWidgets('backgrounding discards old touches', (tester) async {
    final model = GamepadInputModel();
    await showController(tester, model);
    final stick = await tester.startGesture(
      tester.getCenter(control('LS')),
      pointer: 1,
    );
    final button = await tester.startGesture(
      tester.getCenter(control('A')),
      pointer: 2,
    );
    await stick.moveBy(const Offset(20, 0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(model.state, GamepadState.neutral);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await stick.moveBy(const Offset(10, 0));
    await tester.pump();
    expect(model.state, GamepadState.neutral);
    await stick.up();
    await button.up();
  });

  testWidgets('connection loss clears holds and rejects input until restored', (
    tester,
  ) async {
    final model = GamepadInputModel();
    await showController(tester, model);
    final button = await tester.startGesture(tester.getCenter(control('A')));
    await showController(tester, model, enabled: false);
    expect(model.state, GamepadState.neutral);
    await button.up();
    await tester.tapAt(tester.getCenter(control('B')));
    expect(model.state, GamepadState.neutral);
    await showController(tester, model);
    final fresh = await tester.startGesture(tester.getCenter(control('B')));
    expect(model.state.buttons, GamepadButton.b);
    await fresh.up();
  });

  testWidgets('optional visual preview', (tester) async {
    if (!const bool.fromEnvironment('CAPTURE_CONTROLLER')) return;
    await showController(tester, GamepadInputModel());
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('preview')),
    );
    await tester.runAsync(() async {
      final preview = await boundary.toImage(pixelRatio: 2);
      final bytes = await preview.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build').create(recursive: true);
      await File(
        'build/controller-preview.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      preview.dispose();
    });
  });

  testWidgets('digital triggers instantly jump to 100% and release to 0', (
    tester,
  ) async {
    final model = GamepadInputModel();
    await showController(
      tester,
      model,
      stickSettings: const ControllerStickSettings(digitalTriggers: true),
    );
    final lt = await tester.startGesture(tester.getCenter(control('LT')));
    expect(model.state.leftTrigger, 65535);
    await lt.up();
    expect(model.state.leftTrigger, 0);

    final rt = await tester.startGesture(tester.getCenter(control('RT')));
    expect(model.state.rightTrigger, 65535);
    await rt.up();
    expect(model.state.rightTrigger, 0);
  });

  testWidgets('double-tap on stick triggers stick click and releases cleanly', (
    tester,
  ) async {
    final model = GamepadInputModel();
    await showController(tester, model);
    final center = tester.getCenter(control('LS'));
    final tap1 = await tester.startGesture(center);
    await tap1.up();
    expect(model.state.buttons & GamepadButton.l3, 0);

    final tap2 = await tester.startGesture(center);
    expect(model.state.buttons & GamepadButton.l3, GamepadButton.l3);
    await tap2.up();
    expect(model.state.buttons & GamepadButton.l3, 0);
  });

  testWidgets('test pad renders profile, responds to touches, and exits', (
    tester,
  ) async {
    const profile = ControllerProfile(
      id: 'test-pad-profile',
      name: 'Test Pad Profile',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: ControllerTestPadPage(profile: profile),
      ),
    );
    expect(find.text('Exit Test Pad (Test Pad Profile)'), findsOneWidget);
    final a = await tester.startGesture(tester.getCenter(control('A')));
    await tester.pump();
    expect(find.textContaining('Active: A'), findsOneWidget);
    await a.up();
    await tester.pump();
    expect(find.textContaining('Active: None'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('exit-test-pad')));
    await tester.pumpAndSettle();
    expect(find.byType(ControllerTestPadPage), findsNothing);
  });

  testWidgets('PS4 controller displays PlayStation symbols and shoulder labels', (
    tester,
  ) async {
    final model = GamepadInputModel();
    await showController(tester, model, controllerType: ControllerType.ds4);

    expect(find.text('✕'), findsOneWidget);
    expect(find.text('○'), findsOneWidget);
    expect(find.text('□'), findsOneWidget);
    expect(find.text('△'), findsOneWidget);
    expect(find.text('L1'), findsOneWidget);
    expect(find.text('R1'), findsOneWidget);
    expect(find.text('L2'), findsOneWidget);
    expect(find.text('R2'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Options'), findsOneWidget);
    expect(find.text('PS'), findsOneWidget);
  });

  testWidgets('test pad renders PS4 profile and tracks pressed buttons with PS4 labels', (
    tester,
  ) async {
    const profile = ControllerProfile(
      id: 'ps4-test-pad',
      name: 'PS4 Profile',
      controllerType: ControllerType.ds4,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: ControllerTestPadPage(profile: profile),
      ),
    );
    expect(find.text('Exit Test Pad (PS4 Profile)'), findsOneWidget);
    expect(find.text('✕'), findsOneWidget);
    final cross = await tester.startGesture(tester.getCenter(control('A')));
    await tester.pump();
    expect(find.textContaining('Active: ✕'), findsOneWidget);
    await cross.up();
    await tester.pump();
    expect(find.textContaining('Active: None'), findsOneWidget);
  });
}
