import 'package:flutter/material.dart';

import '../client_preferences.dart';
import '../controller_profile.dart';
import 'test_pad_page.dart';

class ProfileManagerPage extends StatefulWidget {
  const ProfileManagerPage({
    super.key,
    required this.preferences,
    required this.initialProfiles,
  });

  final ClientPreferences preferences;
  final ControllerProfileLibrary initialProfiles;

  @override
  State<ProfileManagerPage> createState() => _ProfileManagerPageState();
}

class _ProfileManagerPageState extends State<ProfileManagerPage> {
  late ControllerProfileLibrary _profiles;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _profiles = widget.initialProfiles;
  }

  Future<void> _apply(ControllerProfileLibrary next) async {
    if (identical(next, _profiles)) return;
    setState(() {
      _profiles = next;
      _saving = true;
    });
    try {
      await widget.preferences.saveControllerProfiles(next);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editProfile({ControllerProfile? profile}) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _ProfileNameDialog(
        initialName: profile?.name ?? '',
        editing: profile != null,
      ),
    );
    if (name == null) return;

    final next = profile == null
        ? _profiles.create(
            id: 'profile-${DateTime.now().microsecondsSinceEpoch}',
            name: name,
          )
        : _profiles.rename(profile.id, name);
    if (identical(next, _profiles)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Use a unique name of up to 24 characters.'),
          ),
        );
      }
      return;
    }
    await _apply(next);
  }

  Future<void> _delete(ControllerProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete profile?'),
        content: Text('“${profile.name}” will be removed from this phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _apply(_profiles.remove(profile.id));
  }

  Future<void> _testProfile(ControllerProfile profile) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ControllerTestPadPage(profile: profile),
      ),
    );
  }

  Future<void> _configure(ControllerProfile profile) async {
    var settings = profile.sticks;
    final result = await showModalBottomSheet<ControllerStickSettings>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  profile.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                const Text('Stick & trigger response'),
                const SizedBox(height: 20),
                _SettingSlider(
                  label: 'Dead zone',
                  valueLabel: '${(settings.deadZone * 100).round()}%',
                  value: settings.deadZone,
                  min: 0,
                  max: .30,
                  divisions: 15,
                  onChanged: (value) => setSheetState(
                    () => settings = ControllerStickSettings(
                      deadZone: value,
                      sensitivity: settings.sensitivity,
                      digitalTriggers: settings.digitalTriggers,
                    ),
                  ),
                ),
                _SettingSlider(
                  label: 'Sensitivity',
                  valueLabel: '${settings.sensitivity.toStringAsFixed(1)}×',
                  value: settings.sensitivity,
                  min: .5,
                  max: 1.5,
                  divisions: 10,
                  onChanged: (value) => setSheetState(
                    () => settings = ControllerStickSettings(
                      deadZone: settings.deadZone,
                      sensitivity: value,
                      digitalTriggers: settings.digitalTriggers,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Digital triggers (LT / RT)'),
                  subtitle: const Text(
                    'Instant 100% response on touch without vertical sliding',
                  ),
                  value: settings.digitalTriggers,
                  onChanged: (value) => setSheetState(
                    () => settings = ControllerStickSettings(
                      deadZone: settings.deadZone,
                      sensitivity: settings.sensitivity,
                      digitalTriggers: value,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(context, settings),
                  child: const Text('Save settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null)
      await _apply(_profiles.updateStickSettings(profile.id, result));
  }

  Future<void> _configureButtons(ControllerProfile profile) async {
    var mapping = profile.buttons;
    final result = await showModalBottomSheet<ControllerButtonMapping>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .88,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.name,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const Text(
                              'Button mapping · assignments swap automatically',
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => setSheetState(
                          () => mapping = ControllerButtonMapping.identity,
                        ),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: ControllerButtonMapping.slots.length,
                    itemBuilder: (context, index) {
                      final slot = ControllerButtonMapping.slots[index];
                      final action = mapping.actionFor(slot);
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(child: Text(slot)),
                          title: Text('Position $slot'),
                          trailing: DropdownButton<String>(
                            value: action.id,
                            onChanged: (value) {
                              if (value != null)
                                setSheetState(
                                  () => mapping = mapping.remap(slot, value),
                                );
                            },
                            items: [
                              for (final option in ControllerButtonAction.all)
                                DropdownMenuItem(
                                  value: option.id,
                                  child: Text(option.label),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, mapping),
                    child: const Text('Save mapping'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null)
      await _apply(_profiles.updateButtonMapping(profile.id, result));
  }

  Future<void> _configureLayout(ControllerProfile profile) async {
    var layout = profile.layout;
    const names = {
      'leftStick': 'Left stick',
      'dpad': 'D-pad',
      'rightStick': 'Right stick',
      'actions': 'Action buttons',
    };
    final result = await showModalBottomSheet<ControllerLayoutSettings>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .88,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.name,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const Text('Drag to move · adjust width below'),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => setSheetState(
                          () => layout = ControllerLayoutSettings.defaults,
                        ),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    buildDefaultDragHandles: false,
                    itemCount: layout.order.length,
                    onReorderItem: (oldIndex, newIndex) => setSheetState(
                      () => layout = layout.reorder(oldIndex, newIndex),
                    ),
                    itemBuilder: (context, index) {
                      final zone = layout.order[index];
                      final width = layout.widthFor(zone);
                      return Card(
                        key: ValueKey(zone),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Icon(Icons.drag_indicator),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      names[zone]!,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                    Row(
                                      children: [
                                        const Text('Narrow'),
                                        Expanded(
                                          child: Slider(
                                            value: width.toDouble(),
                                            min: 2,
                                            max: 4,
                                            divisions: 2,
                                            label: '$width',
                                            onChanged: (value) => setSheetState(
                                              () => layout = layout.resize(
                                                zone,
                                                value.round(),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const Text('Wide'),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, layout),
                    child: const Text('Save layout'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null)
      await _apply(_profiles.updateLayout(profile.id, result));
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) Navigator.of(context).pop(_profiles);
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Controller profiles'),
        actions: [
          IconButton(
            tooltip: 'Test selected profile',
            onPressed: () => _testProfile(_profiles.selected),
            icon: const Icon(Icons.sports_esports_rounded),
          ),
          IconButton(
            tooltip: 'New profile',
            onPressed: _saving ? null : () => _editProfile(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : () => _editProfile(),
        icon: const Icon(Icons.add),
        label: const Text('New profile'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 8, 8, 16),
            child: Text(
              'Choose the controls you use before connecting. Profiles stay only on this phone.',
            ),
          ),
          IgnorePointer(
            ignoring: _saving,
            child: RadioGroup<String>(
              groupValue: _profiles.selected.id,
              onChanged: (id) {
                if (id != null) _apply(_profiles.select(id));
              },
              child: Column(
                children: [
                  for (final profile in _profiles.profiles)
                    Card(
                      child: RadioListTile<String>(
                        value: profile.id,
                        title: Text(profile.name),
                        subtitle: Text(
                          profile.id == ControllerProfile.defaultId
                              ? 'Standard touch layout'
                              : 'Ready for your future control settings',
                        ),
                        secondary: profile.id == ControllerProfile.defaultId
                            ? IconButton(
                                tooltip: 'Test controller',
                                icon: const Icon(Icons.sports_esports_rounded),
                                onPressed: () => _testProfile(profile),
                              )
                            : PopupMenuButton<String>(
                                onSelected: (action) {
                                  if (action == 'test') _testProfile(profile);
                                  if (action == 'rename')
                                    _editProfile(profile: profile);
                                  if (action == 'delete') _delete(profile);
                                  if (action == 'settings') _configure(profile);
                                  if (action == 'mapping')
                                    _configureButtons(profile);
                                  if (action == 'layout')
                                    _configureLayout(profile);
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'test',
                                    child: Text('Test controller'),
                                  ),
                                  PopupMenuItem(
                                    value: 'settings',
                                    child: Text('Stick & trigger settings'),
                                  ),
                                  PopupMenuItem(
                                    value: 'mapping',
                                    child: Text('Button mapping'),
                                  ),
                                  PopupMenuItem(
                                    value: 'layout',
                                    child: Text('Layout and sizes'),
                                  ),
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Text('Rename'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [Text(label), const Spacer(), Text(valueLabel)]),
      Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: valueLabel,
        onChanged: onChanged,
      ),
    ],
  );
}

class _ProfileNameDialog extends StatefulWidget {
  const _ProfileNameDialog({required this.initialName, required this.editing});

  final String initialName;
  final bool editing;

  @override
  State<_ProfileNameDialog> createState() => _ProfileNameDialogState();
}

class _ProfileNameDialogState extends State<_ProfileNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.editing ? 'Rename profile' : 'New profile'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 24,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        labelText: 'Profile name',
        hintText: 'Friday party',
      ),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(widget.editing ? 'Save' : 'Create'),
      ),
    ],
  );
}
