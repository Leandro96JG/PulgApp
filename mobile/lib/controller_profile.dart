import 'dart:convert';
import 'dart:math' as math;

import 'gamepad_state.dart';

/// A versioned local container for controller settings.
///
/// Profiles intentionally contain no transport data: endpoint, PIN and session
/// credentials cannot be copied into a controller profile. Future remapping and
/// sensitivity settings can be added through a new schema version.
final class ControllerStickSettings {
  const ControllerStickSettings({
    this.deadZone = .10,
    this.sensitivity = 1,
    this.digitalTriggers = false,
  });

  static const defaults = ControllerStickSettings();
  final double deadZone;
  final double sensitivity;
  final bool digitalTriggers;

  Map<String, Object> toJson() => {
    'deadZone': deadZone,
    'sensitivity': sensitivity,
    'digitalTriggers': digitalTriggers,
  };

  static ControllerStickSettings? tryParse(Object? value) {
    if (value is! Map) return null;
    final deadZone = value['deadZone'];
    final sensitivity = value['sensitivity'];
    if (deadZone is! num || sensitivity is! num) return null;
    final digitalTriggers = value['digitalTriggers'] is bool
        ? value['digitalTriggers'] as bool
        : false;
    final settings = ControllerStickSettings(
      deadZone: deadZone.toDouble(),
      sensitivity: sensitivity.toDouble(),
      digitalTriggers: digitalTriggers,
    );
    return settings.isValid ? settings : null;
  }

  bool get isValid =>
      deadZone >= 0 &&
      deadZone <= .30 &&
      sensitivity >= .5 &&
      sensitivity <= 1.5;

  /// Maps a radial stick distance while preserving neutral safety.
  double mapMagnitude(double magnitude) {
    final safe = magnitude.clamp(0.0, 1.0);
    if (safe <= deadZone) return 0;
    return (((safe - deadZone) / (1 - deadZone)) * sensitivity).clamp(0.0, 1.0);
  }
}

final class ControllerButtonAction {
  const ControllerButtonAction(this.id, this.label, this.bit);
  final String id;
  final String label;
  final int bit;

  static const all = [
    ControllerButtonAction('a', 'A', GamepadButton.a),
    ControllerButtonAction('b', 'B', GamepadButton.b),
    ControllerButtonAction('x', 'X', GamepadButton.x),
    ControllerButtonAction('y', 'Y', GamepadButton.y),
    ControllerButtonAction('lb', 'LB', GamepadButton.lb),
    ControllerButtonAction('rb', 'RB', GamepadButton.rb),
    ControllerButtonAction('back', 'Back', GamepadButton.back),
    ControllerButtonAction('guide', 'Guide', GamepadButton.guide),
    ControllerButtonAction('start', 'Start', GamepadButton.start),
    ControllerButtonAction('l3', 'L3', GamepadButton.l3),
    ControllerButtonAction('r3', 'R3', GamepadButton.r3),
  ];

  static ControllerButtonAction fromId(String id) =>
      all.firstWhere((action) => action.id == id);
}

final class ControllerButtonMapping {
  const ControllerButtonMapping._(this.assignments);

  static const slots = [
    'A',
    'B',
    'X',
    'Y',
    'LB',
    'RB',
    'Back',
    'Guide',
    'Start',
    'L3',
    'R3',
  ];
  static const identity = ControllerButtonMapping._({
    'A': 'a',
    'B': 'b',
    'X': 'x',
    'Y': 'y',
    'LB': 'lb',
    'RB': 'rb',
    'Back': 'back',
    'Guide': 'guide',
    'Start': 'start',
    'L3': 'l3',
    'R3': 'r3',
  });

  final Map<String, String> assignments;

  ControllerButtonAction actionFor(String slot) =>
      ControllerButtonAction.fromId(assignments[slot]!);
  Iterable<String> get visibleChanges => slots
      .where(
        (slot) => actionFor(slot).label.toLowerCase() != slot.toLowerCase(),
      )
      .map((slot) => '$slot → ${actionFor(slot).label}');
  String get visibleSummary {
    final changes = visibleChanges.toList();
    return changes.isEmpty ? 'Default button mapping' : changes.join('  ·  ');
  }

  Map<String, Object> toJson() => Map<String, Object>.from(assignments);

  static ControllerButtonMapping? tryParse(Object? value) {
    if (value is! Map) return null;
    final allowed = ControllerButtonAction.all
        .map((action) => action.id)
        .toSet();
    final parsed = <String, String>{};
    for (final slot in slots) {
      final action = value[slot];
      if (action is! String || !allowed.contains(action)) return null;
      parsed[slot] = action;
    }
    if (parsed.values.toSet().length != slots.length) return null;
    return ControllerButtonMapping._(Map.unmodifiable(parsed));
  }

  ControllerButtonMapping remap(String slot, String actionId) {
    if (!slots.contains(slot) || assignments[slot] == actionId) return this;
    if (!ControllerButtonAction.all.any((action) => action.id == actionId))
      return this;
    final otherSlot = assignments.entries
        .firstWhere((entry) => entry.value == actionId)
        .key;
    final next = Map<String, String>.from(assignments);
    next[otherSlot] = next[slot]!;
    next[slot] = actionId;
    return ControllerButtonMapping._(Map.unmodifiable(next));
  }
}

final class ControllerLayoutSettings {
  const ControllerLayoutSettings._(this.order, this.widths);

  static const zones = ['leftStick', 'dpad', 'rightStick', 'actions'];
  static const defaults = ControllerLayoutSettings._(
    ['leftStick', 'dpad', 'rightStick', 'actions'],
    {'leftStick': 3, 'dpad': 2, 'rightStick': 2, 'actions': 3},
  );

  final List<String> order;
  final Map<String, int> widths;

  int widthFor(String zone) => widths[zone]!;
  Map<String, Object> toJson() => {'order': order, 'widths': widths};

  static ControllerLayoutSettings? tryParse(Object? value) {
    if (value is! Map || value['order'] is! List || value['widths'] is! Map)
      return null;
    final order = (value['order'] as List).whereType<String>().toList();
    if (order.length != zones.length ||
        order.toSet().length != zones.length ||
        !order.toSet().containsAll(zones))
      return null;
    final rawWidths = value['widths'] as Map;
    final widths = <String, int>{};
    for (final zone in zones) {
      final width = rawWidths[zone];
      if (width is! int || width < 2 || width > 4) return null;
      widths[zone] = width;
    }
    if (widths.values.fold<int>(0, (sum, width) => sum + width) != 10)
      return null;
    return ControllerLayoutSettings._(
      List.unmodifiable(order),
      Map.unmodifiable(widths),
    );
  }

  ControllerLayoutSettings reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= order.length ||
        newIndex < 0 ||
        newIndex >= order.length) {
      return this;
    }
    final next = [...order];
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    return ControllerLayoutSettings._(List.unmodifiable(next), widths);
  }

  /// Resizes a zone in grid units and redistributes the difference safely.
  ControllerLayoutSettings resize(String zone, int requestedWidth) {
    if (!zones.contains(zone)) return this;
    final next = Map<String, int>.from(widths);
    final target = requestedWidth.clamp(2, 4);
    var delta = target - next[zone]!;
    if (delta == 0) return this;
    next[zone] = target;
    for (final other in order.reversed.where(
      (candidate) => candidate != zone,
    )) {
      if (delta > 0) {
        final available = next[other]! - 2;
        final take = math.min(delta, available);
        next[other] = next[other]! - take;
        delta -= take;
      } else {
        final available = 4 - next[other]!;
        final give = math.min(-delta, available);
        next[other] = next[other]! + give;
        delta += give;
      }
      if (delta == 0) break;
    }
    if (delta != 0) return this;
    return ControllerLayoutSettings._(order, Map.unmodifiable(next));
  }
}

final class ControllerProfile {
  const ControllerProfile({
    required this.id,
    required this.name,
    this.sticks = ControllerStickSettings.defaults,
    this.buttons = ControllerButtonMapping.identity,
    this.layout = ControllerLayoutSettings.defaults,
  });

  static const defaultId = 'default';
  static const currentVersion = 4;

  final String id;
  final String name;
  final ControllerStickSettings sticks;
  final ControllerButtonMapping buttons;
  final ControllerLayoutSettings layout;

  static const fallback = ControllerProfile(id: defaultId, name: 'Default');

  Map<String, Object> toJson() => {
    'version': currentVersion,
    'id': id,
    'name': name,
    'sticks': sticks.toJson(),
    'buttons': buttons.toJson(),
    'layout': layout.toJson(),
  };

  static ControllerProfile? tryParse(Object? value) {
    if (value is! Map) return null;
    final version = value['version'];
    final id = value['id'];
    final name = value['name'];
    if ((version != 1 &&
            version != 2 &&
            version != 3 &&
            version != currentVersion) ||
        id is! String ||
        name is! String) {
      return null;
    }
    final cleanId = id.trim();
    final cleanName = name.trim();
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,48}$').hasMatch(cleanId) ||
        cleanName.isEmpty ||
        cleanName.length > 24) {
      return null;
    }
    final sticks = version == 1
        ? ControllerStickSettings.defaults
        : ControllerStickSettings.tryParse(value['sticks']);
    if (sticks == null) return null;
    final buttons = version == 3 || version == currentVersion
        ? ControllerButtonMapping.tryParse(value['buttons'])
        : ControllerButtonMapping.identity;
    if (buttons == null) return null;
    final layout = version == currentVersion
        ? ControllerLayoutSettings.tryParse(value['layout'])
        : ControllerLayoutSettings.defaults;
    if (layout == null) return null;
    return ControllerProfile(
      id: cleanId,
      name: cleanName,
      sticks: sticks,
      buttons: buttons,
      layout: layout,
    );
  }
}

/// Immutable profile library with a safe default for malformed local storage.
final class ControllerProfileLibrary {
  ControllerProfileLibrary._(this.profiles, this.selectedId);

  static const currentVersion = 4;
  static const _maximumProfiles = 12;

  final List<ControllerProfile> profiles;
  final String selectedId;

  int get version => currentVersion;

  factory ControllerProfileLibrary.initial() => ControllerProfileLibrary._(
    const [ControllerProfile.fallback],
    ControllerProfile.defaultId,
  );

  ControllerProfile get selected =>
      profiles.where((profile) => profile.id == selectedId).firstOrNull ??
      profiles.first;

  factory ControllerProfileLibrary.decode(String? source) {
    if (source == null || source.isEmpty)
      return ControllerProfileLibrary.initial();
    try {
      final parsed = jsonDecode(source);
      if (parsed is! Map ||
          (parsed['version'] != 1 &&
              parsed['version'] != 2 &&
              parsed['version'] != 3 &&
              parsed['version'] != currentVersion)) {
        return ControllerProfileLibrary.initial();
      }
      final profilesValue = parsed['profiles'];
      if (profilesValue is! List) return ControllerProfileLibrary.initial();
      final profiles = <ControllerProfile>[ControllerProfile.fallback];
      final ids = {ControllerProfile.defaultId};
      for (final value in profilesValue) {
        final profile = ControllerProfile.tryParse(value);
        if (profile != null &&
            ids.add(profile.id) &&
            profile.id != ControllerProfile.defaultId &&
            profiles.length < _maximumProfiles) {
          profiles.add(profile);
        }
      }
      final requestedId = parsed['selectedId'];
      final selectedId = requestedId is String && ids.contains(requestedId)
          ? requestedId
          : ControllerProfile.defaultId;
      return ControllerProfileLibrary._(
        List.unmodifiable(profiles),
        selectedId,
      );
    } on FormatException {
      return ControllerProfileLibrary.initial();
    }
  }

  String encode() => jsonEncode({
    'version': currentVersion,
    'selectedId': selected.id,
    'profiles': profiles.map((profile) => profile.toJson()).toList(),
  });

  ControllerProfileLibrary select(String id) =>
      profiles.any((profile) => profile.id == id)
      ? ControllerProfileLibrary._(profiles, id)
      : this;

  ControllerProfileLibrary create({required String id, required String name}) {
    final profile = ControllerProfile.tryParse({
      'version': ControllerProfile.currentVersion,
      'id': id,
      'name': name,
      'sticks': ControllerStickSettings.defaults.toJson(),
      'buttons': ControllerButtonMapping.identity.toJson(),
      'layout': ControllerLayoutSettings.defaults.toJson(),
    });
    if (profile == null ||
        profiles.length >= _maximumProfiles ||
        profiles.any((current) => current.id == profile.id)) {
      return this;
    }
    return ControllerProfileLibrary._(
      List.unmodifiable([...profiles, profile]),
      profile.id,
    );
  }

  ControllerProfileLibrary rename(String id, String name) {
    if (id == ControllerProfile.defaultId) return this;
    final existing = profiles.where((profile) => profile.id == id).firstOrNull;
    final replacement = existing == null
        ? null
        : ControllerProfile.tryParse({
            'version': ControllerProfile.currentVersion,
            'id': id,
            'name': name,
            'sticks': existing.sticks.toJson(),
            'buttons': existing.buttons.toJson(),
            'layout': existing.layout.toJson(),
          });
    if (replacement == null) return this;
    return ControllerProfileLibrary._(
      List.unmodifiable([
        for (final profile in profiles)
          if (profile.id == id) replacement else profile,
      ]),
      selectedId,
    );
  }

  ControllerProfileLibrary updateStickSettings(
    String id,
    ControllerStickSettings settings,
  ) {
    if (!settings.isValid) return this;
    final existing = profiles.where((profile) => profile.id == id).firstOrNull;
    if (existing == null) return this;
    final replacement = ControllerProfile(
      id: id,
      name: existing.name,
      sticks: settings,
      buttons: existing.buttons,
      layout: existing.layout,
    );
    return ControllerProfileLibrary._(
      List.unmodifiable([
        for (final profile in profiles)
          if (profile.id == id) replacement else profile,
      ]),
      selectedId,
    );
  }

  ControllerProfileLibrary updateButtonMapping(
    String id,
    ControllerButtonMapping mapping,
  ) {
    final existing = profiles.where((profile) => profile.id == id).firstOrNull;
    if (existing == null) return this;
    final replacement = ControllerProfile(
      id: id,
      name: existing.name,
      sticks: existing.sticks,
      buttons: mapping,
      layout: existing.layout,
    );
    return ControllerProfileLibrary._(
      List.unmodifiable([
        for (final profile in profiles)
          if (profile.id == id) replacement else profile,
      ]),
      selectedId,
    );
  }

  ControllerProfileLibrary updateLayout(
    String id,
    ControllerLayoutSettings layout,
  ) {
    final existing = profiles.where((profile) => profile.id == id).firstOrNull;
    if (existing == null) return this;
    final replacement = ControllerProfile(
      id: id,
      name: existing.name,
      sticks: existing.sticks,
      buttons: existing.buttons,
      layout: layout,
    );
    return ControllerProfileLibrary._(
      List.unmodifiable([
        for (final profile in profiles)
          if (profile.id == id) replacement else profile,
      ]),
      selectedId,
    );
  }

  ControllerProfileLibrary remove(String id) {
    if (id == ControllerProfile.defaultId ||
        !profiles.any((profile) => profile.id == id)) {
      return this;
    }
    final remaining = List<ControllerProfile>.unmodifiable(
      profiles.where((profile) => profile.id != id),
    );
    return ControllerProfileLibrary._(
      remaining,
      selectedId == id ? ControllerProfile.defaultId : selectedId,
    );
  }
}
