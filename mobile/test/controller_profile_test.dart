import 'dart:convert';

import 'package:pulgapp_mobile/controller_profile.dart';
import 'package:pulgapp_mobile/gamepad_state.dart';
import 'package:test/test.dart';

void main() {
  test(
    'invalid or unknown-version storage recovers to the default profile',
    () {
      expect(
        ControllerProfileLibrary.decode('{not-json').selected.name,
        'Default',
      );
      expect(
        ControllerProfileLibrary.decode(
          jsonEncode({'version': 99, 'selectedId': 'custom', 'profiles': []}),
        ).selected.id,
        ControllerProfile.defaultId,
      );
    },
  );

  test('round-trips a selected, renamed local profile', () {
    final profiles = ControllerProfileLibrary.initial()
        .create(id: 'arcade', name: ' Arcade room ')
        .rename('arcade', 'Friday party')
        .select('arcade');

    final restored = ControllerProfileLibrary.decode(profiles.encode());
    expect(restored.selected.id, 'arcade');
    expect(restored.selected.name, 'Friday party');
    expect(restored.profiles, hasLength(2));
    expect(restored.version, ControllerProfileLibrary.currentVersion);
  });

  test('stick settings persist and apply a safe radial response', () {
    const settings = ControllerStickSettings(deadZone: .20, sensitivity: 1.5);
    final profiles = ControllerProfileLibrary.initial()
        .create(id: 'precise', name: 'Precise')
        .updateStickSettings('precise', settings)
        .select('precise');
    final restored = ControllerProfileLibrary.decode(profiles.encode());
    expect(restored.selected.sticks.deadZone, .20);
    expect(restored.selected.sticks.sensitivity, 1.5);
    expect(settings.mapMagnitude(.20), 0);
    expect(settings.mapMagnitude(.60), closeTo(.75, .0001));
    expect(settings.mapMagnitude(1), 1);
  });

  test('button remapping swaps assignments and survives persistence', () {
    final mapping = ControllerButtonMapping.identity.remap('A', 'b');
    expect(mapping.actionFor('A').label, 'B');
    expect(mapping.actionFor('B').label, 'A');
    final profiles = ControllerProfileLibrary.initial()
        .create(id: 'southpaw', name: 'Southpaw')
        .updateButtonMapping('southpaw', mapping)
        .select('southpaw');
    final restored = ControllerProfileLibrary.decode(profiles.encode());
    expect(restored.selected.buttons.actionFor('A').bit, GamepadButton.b);
    expect(restored.selected.buttons.actionFor('B').bit, GamepadButton.a);
  });

  test('layout reorders and resizes zones without losing grid safety', () {
    final layout = ControllerLayoutSettings.defaults
        .reorder(3, 0)
        .resize('leftStick', 4);
    expect(layout.order.first, 'actions');
    expect(
      ControllerLayoutSettings.defaults.reorder(0, 3).order.last,
      'leftStick',
    );
    expect(layout.widthFor('leftStick'), 4);
    expect(layout.widths.values.reduce((a, b) => a + b), 10);
    expect(
      layout.widths.values.every((width) => width >= 2 && width <= 4),
      isTrue,
    );
    final profiles = ControllerProfileLibrary.initial()
        .create(id: 'custom-layout', name: 'Custom layout')
        .updateLayout('custom-layout', layout)
        .select('custom-layout');
    final restored = ControllerProfileLibrary.decode(profiles.encode());
    expect(restored.selected.layout.order.first, 'actions');
    expect(restored.selected.layout.widthFor('leftStick'), 4);
  });

  test('rejects malformed entries and preserves a valid selected profile', () {
    final profiles = ControllerProfileLibrary.decode(
      jsonEncode({
        'version': 1,
        'selectedId': 'good',
        'profiles': [
          {'version': 1, 'id': 'good', 'name': 'Kitchen'},
          {'version': 1, 'id': 'good', 'name': 'Duplicate'},
          {'version': 1, 'id': '', 'name': 'Bad id'},
          {'version': 2, 'id': 'old', 'name': 'Old schema'},
        ],
      }),
    );

    expect(profiles.selected.name, 'Kitchen');
    expect(
      profiles.profiles.map((profile) => profile.id),
      containsAll(['default', 'good']),
    );
    expect(profiles.profiles, hasLength(2));
  });

  test(
    'cannot remove the fallback profile and deletion selects a safe fallback',
    () {
      final created = ControllerProfileLibrary.initial().create(
        id: 'guest',
        name: 'Guest',
      );
      expect(created.remove(ControllerProfile.defaultId), same(created));
      expect(
        created.select('guest').remove('guest').selected.id,
        ControllerProfile.defaultId,
      );
    },
  );

  test('digital triggers setting persists and defaults to false', () {
    expect(ControllerStickSettings.defaults.digitalTriggers, isFalse);
    const digitalSettings = ControllerStickSettings(
      deadZone: .15,
      sensitivity: 1.2,
      digitalTriggers: true,
    );
    final profiles = ControllerProfileLibrary.initial()
        .create(id: 'arcade', name: 'Arcade')
        .updateStickSettings('arcade', digitalSettings)
        .select('arcade');
    final restored = ControllerProfileLibrary.decode(profiles.encode());
    expect(restored.selected.sticks.digitalTriggers, isTrue);
    expect(restored.selected.sticks.deadZone, .15);
    expect(restored.selected.sticks.sensitivity, 1.2);
  });
}
