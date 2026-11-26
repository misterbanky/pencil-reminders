import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PencilRemindersApp());
}

enum BackdropStyle { clean, grid, drift }

class ReminderItem {
  final String id;
  String title;
  String time24; // "HH:mm"
  String repeat; // Once | Daily | Weekdays
  String soundId;
  String? customAudioPath;
  String? customAudioName;
  bool enabled;
  int snoozeCount;

  ReminderItem({
    required this.id,
    required this.title,
    required this.time24,
    required this.repeat,
    required this.soundId,
    this.customAudioPath,
    this.customAudioName,
    this.enabled = true,
    this.snoozeCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'time24': time24,
        'repeat': repeat,
        'soundId': soundId,
        'customAudioPath': customAudioPath,
        'customAudioName': customAudioName,
        'enabled': enabled,
        'snoozeCount': snoozeCount,
      };

  factory ReminderItem.fromJson(Map<String, dynamic> json) => ReminderItem(
        id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: json['title']?.toString() ?? 'Reminder',
        time24: json['time24']?.toString() ?? '08:00',
        repeat: json['repeat']?.toString() ?? 'Once',
        soundId: json['soundId']?.toString() ?? 'chime',
        customAudioPath: json['customAudioPath']?.toString(),
        customAudioName: json['customAudioName']?.toString(),
        enabled: json['enabled'] != false,
        snoozeCount: (json['snoozeCount'] as num?)?.toInt() ?? 0,
      );
}

class SoundOption {
  final String id;
  final String name;
  final double baseFreq;

  const SoundOption({required this.id, required this.name, required this.baseFreq});
}

const List<SoundOption> kBuiltInSounds = [
  SoundOption(id: 'chime', name: 'Morning Chime', baseFreq: 523.25),
  SoundOption(id: 'pulse', name: 'Clear Pulse', baseFreq: 659.25),
  SoundOption(id: 'bell', name: 'Soft Bell', baseFreq: 440.0),
  SoundOption(id: 'marimba', name: 'Warm Cadence', baseFreq: 587.33),
];

class PencilRemindersApp extends StatefulWidget {
  const PencilRemindersApp({super.key});

  @override
  State<PencilRemindersApp> createState() => _PencilRemindersAppState();
}

class _PencilRemindersAppState extends State<PencilRemindersApp> {
  static const String _remindersKey = 'pencil_reminders_items_v1';
  static const String _themeKey = 'pencil_reminders_dark_v1';
  static const String _backdropKey = 'pencil_reminders_backdrop_v1';

  bool _isDark = false;
  BackdropStyle _backdrop = BackdropStyle.clean;
  List<ReminderItem> _reminders = [];
  ReminderItem? _activeAlarm;

  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _alarmLoopTimer;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool(_themeKey) ?? false;
    final backdropName = prefs.getString(_backdropKey) ?? 'clean';
    final rawList = prefs.getString(_remindersKey);

    List<ReminderItem> loaded = [];
    if (rawList != null) {
      try {
        final decoded = jsonDecode(rawList) as List<dynamic>;
        loaded = decoded
            .map((e) => ReminderItem.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    if (loaded.isEmpty) {
      loaded = [
        ReminderItem(
          id: '1',
          title: 'Morning stretch & water',
          time24: '06:30',
          repeat: 'Daily',
          soundId: 'chime',
          enabled: true,
        ),
        ReminderItem(
          id: '2',
          title: 'Prepare sketch & lesson notes',
          time24: '14:00',
          repeat: 'Weekdays',
          soundId: 'pulse',
          enabled: true,
        ),
        ReminderItem(
          id: '3',
          title: 'Check workshop tools',
          time24: '18:15',
          repeat: 'Once',
          soundId: 'bell',
          enabled: false,
        ),
      ];
    }

    setState(() {
      _isDark = isDark;
      _backdrop = BackdropStyle.values.firstWhere(
        (b) => b.name == backdropName,
        orElse: () => BackdropStyle.clean,
      );
      _reminders = loaded;
    });
  }

  Future<void> _saveReminders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _remindersKey,
      jsonEncode(_reminders.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _toggleTheme() async {
    final next = !_isDark;
    setState(() => _isDark = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themeKey, next);
  }

  Future<void> _setBackdrop(BackdropStyle style) async {
    setState(() => _backdrop = style);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backdropKey, style.name);
  }

  Future<void> _playCustomOrPreview(ReminderItem item, {bool loop = false}) async {
    await _stopAlarmAudio();
    if (item.soundId == 'custom' &&
        item.customAudioPath != null &&
        item.customAudioPath!.isNotEmpty) {
      await _audioPlayer.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.stop);
      await _audioPlayer.play(DeviceFileSource(item.customAudioPath!));
    }
  }

  Future<void> _startAlarm(ReminderItem item) async {
    setState(() => _activeAlarm = item);
    if (item.soundId == 'custom' &&
        item.customAudioPath != null &&
        item.customAudioPath!.isNotEmpty) {
      await _playCustomOrPreview(item, loop: true);
    }
  }

  Future<void> _stopAlarmAudio() async {
    _alarmLoopTimer?.cancel();
    _alarmLoopTimer = null;
    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  Future<void> _dismissAlarm() async {
    await _stopAlarmAudio();
    if (_activeAlarm != null) {
      _activeAlarm!.snoozeCount = 0;
      await _saveReminders();
    }
    setState(() => _activeAlarm = null);
  }

  Future<void> _snoozeAlarm() async {
    await _stopAlarmAudio();
    final current = _activeAlarm;
    if (current == null) return;
    current.snoozeCount += 1;
    await _saveReminders();
    setState(() => _activeAlarm = null);

    // TODO: Wire this 5-minute snooze trigger to AndroidAlarmManager.oneShotAt
    // for reliable background wakeups even when the screen is locked.
    _alarmLoopTimer = Timer(const Duration(minutes: 5), () {
      if (mounted) {
        _startAlarm(current);
      }
    });
  }

  @override
  void dispose() {
    _stopAlarmAudio();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = _isDark
        ? const ColorScheme.dark(
            primary: Color(0xFFF59E0B),
            onPrimary: Color(0xFF111113),
            surface: Color(0xFF1B1B1F),
            onSurface: Color(0xFFF4F4F5),
            error: Color(0xFFEF4444),
          )
        : const ColorScheme.light(
            primary: Color(0xFFD97706),
            onPrimary: Color(0xFFFFFFFF),
            surface: Color(0xFFFFFFFF),
            onSurface: Color(0xFF18181B),
            error: Color(0xFFDC2626),
          );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Reminders',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: _isDark ? const Color(0xFF111113) : const Color(0xFFF6F4EF),
      ),
      home: BackdropShell(
        backdrop: _backdrop,
        isDark: _isDark,
        child: _activeAlarm != null
            ? AlarmTakeoverScreen(
                reminder: _activeAlarm!,
                isDark: _isDark,
                onSnooze: _snoozeAlarm,
                onDismiss: _dismissAlarm,
              )
            : ReminderListScreen(
                reminders: _reminders,
                isDark: _isDark,
                onToggleTheme: _toggleTheme,
                onTestAlarm: () {
                  final target = _reminders.firstWhere(
                    (r) => r.enabled,
                    orElse: () => _reminders.first,
                  );
                  _startAlarm(target);
                },
                onToggleEnabled: (item, val) async {
                  setState(() => item.enabled = val);
                  await _saveReminders();
                },
                onSaveReminder: (item, isNew) async {
                  setState(() {
                    if (isNew) {
                      _reminders.insert(0, item);
                    } else {
                      final idx = _reminders.indexWhere((r) => r.id == item.id);
                      if (idx != -1) _reminders[idx] = item;
                    }
                  });
                  await _saveReminders();
                },
                onDeleteReminder: (id) async {
                  setState(() => _reminders.removeWhere((r) => r.id == id));
                  await _saveReminders();
                },
                backdrop: _backdrop,
                onSelectBackdrop: _setBackdrop,
                onPreviewAudio: (item) => _playCustomOrPreview(item, loop: false),
              ),
      ),
    );
  }
}

class BackdropShell extends StatefulWidget {
  final BackdropStyle backdrop;
  final bool isDark;
  final Widget child;

  const BackdropShell({
    super.key,
    required this.backdrop,
    required this.isDark,
    required this.child,
  });

  @override
  State<BackdropShell> createState() => _BackdropShellState();
}

class _BackdropShellState extends State<BackdropShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _driftController;

  @override
  void initState() {
    super.initState();
    _driftController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _driftController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _driftController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _BackdropPainter(
                    style: widget.backdrop,
                    isDark: widget.isDark,
                    driftValue: _driftController.value,
                  ),
                );
              },
            ),
          ),
        ),
        Positioned.fill(child: widget.child),
      ],
    );
  }
}

class _BackdropPainter extends CustomPainter {
  final BackdropStyle style;
  final bool isDark;
  final double driftValue;

  _BackdropPainter({
    required this.style,
    required this.isDark,
    required this.driftValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final accent = isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706);

    if (style == BackdropStyle.clean) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: isDark ? 0.14 : 0.13),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(
            center: Offset(size.width * 0.88, size.height * 0.08),
            radius: size.width * 0.65,
          ),
        );
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }

    if (style == BackdropStyle.grid) {
      const step = 28.0;
      final linePaint = Paint()
        ..color = (isDark ? Colors.white : Colors.black)
            .withValues(alpha: isDark ? 0.10 : 0.11)
        ..strokeWidth = 1.0;

      for (double x = 0; x <= size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
      }
      for (double y = 0; y <= size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      }
      return;
    }

    // BackdropStyle.drift
    final offsetX = math.sin(driftValue * math.pi * 2) * 14;
    final offsetY = math.cos(driftValue * math.pi * 2) * 10;

    final warmPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: isDark ? 0.16 : 0.17),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.24 + offsetX, size.height * 0.25 + offsetY),
          radius: size.width * 0.65,
        ),
      );
    canvas.drawRect(Offset.zero & size, warmPaint);
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) {
    return oldDelegate.style != style ||
        oldDelegate.isDark != isDark ||
        oldDelegate.driftValue != driftValue;
  }
}

class ReminderListScreen extends StatelessWidget {
  final List<ReminderItem> reminders;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onTestAlarm;
  final Future<void> Function(ReminderItem item, bool enabled) onToggleEnabled;
  final Future<void> Function(ReminderItem item, bool isNew) onSaveReminder;
  final Future<void> Function(String id) onDeleteReminder;
  final BackdropStyle backdrop;
  final Future<void> Function(BackdropStyle style) onSelectBackdrop;
  final Future<void> Function(ReminderItem item) onPreviewAudio;

  const ReminderListScreen({
    super.key,
    required this.reminders,
    required this.isDark,
    required this.onToggleTheme,
    required this.onTestAlarm,
    required this.onToggleEnabled,
    required this.onSaveReminder,
    required this.onDeleteReminder,
    required this.backdrop,
    required this.onSelectBackdrop,
    required this.onPreviewAudio,
  });

  String _format12h(String time24) {
    final parts = time24.split(':');
    final hour24 = int.tryParse(parts.first) ?? 8;
    final minute = parts.length > 1 ? parts[1].padLeft(2, '0') : '00';
    final suffix = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour12:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = isDark ? const Color(0xFF9E9EA8) : const Color(0xFF6B6A66);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reminders', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(
              'Tap a card to edit',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: onTestAlarm,
            child: const Text('Test', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          IconButton(
            onPressed: onToggleTheme,
            icon: Icon(isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded),
            tooltip: 'Toggle Theme',
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
        itemCount: reminders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = reminders[index];
          return Opacity(
            opacity: item.enabled ? 1.0 : 0.54,
            child: Material(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _openEditor(context, item, isNew: false),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.11),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _format12h(item.time24),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: item.enabled,
                        onChanged: (val) => onToggleEnabled(item, val),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(
          context,
          ReminderItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: '',
            time24: '08:00',
            repeat: 'Once',
            soundId: 'chime',
            enabled: true,
          ),
          isNew: true,
        ),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, ReminderItem draft, {required bool isNew}) async {
    final result = await Navigator.of(context).push<_EditorResult>(
      MaterialPageRoute(
        builder: (_) => ReminderEditorScreen(
          initialItem: draft,
          isNew: isNew,
          isDark: isDark,
          backdrop: backdrop,
          onSelectBackdrop: onSelectBackdrop,
          onPreviewAudio: onPreviewAudio,
        ),
      ),
    );

    if (result == null) return;
    if (result.deleted) {
      await onDeleteReminder(draft.id);
    } else if (result.savedItem != null) {
      await onSaveReminder(result.savedItem!, isNew);
    }
  }
}

class _EditorResult {
  final ReminderItem? savedItem;
  final bool deleted;
  const _EditorResult({this.savedItem, this.deleted = false});
}

class ReminderEditorScreen extends StatefulWidget {
  final ReminderItem initialItem;
  final bool isNew;
  final bool isDark;
  final BackdropStyle backdrop;
  final Future<void> Function(BackdropStyle style) onSelectBackdrop;
  final Future<void> Function(ReminderItem item) onPreviewAudio;

  const ReminderEditorScreen({
    super.key,
    required this.initialItem,
    required this.isNew,
    required this.isDark,
    required this.backdrop,
    required this.onSelectBackdrop,
    required this.onPreviewAudio,
  });

  @override
  State<ReminderEditorScreen> createState() => _ReminderEditorScreenState();
}

class _ReminderEditorScreenState extends State<ReminderEditorScreen> {
  late final TextEditingController _titleController;
  late String _time24;
  late String _repeat;
  late String _soundId;
  String? _customAudioPath;
  String? _customAudioName;
  late BackdropStyle _currentBackdrop;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialItem.title);
    _time24 = widget.initialItem.time24;
    _repeat = widget.initialItem.repeat;
    _soundId = widget.initialItem.soundId;
    _customAudioPath = widget.initialItem.customAudioPath;
    _customAudioName = widget.initialItem.customAudioName;
    _currentBackdrop = widget.backdrop;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final parts = _time24.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 8,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        _time24 =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _pickAudioFile() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (picked != null && picked.files.isNotEmpty) {
      final file = picked.files.first;
      if (file.path != null) {
        setState(() {
          _customAudioPath = file.path;
          _customAudioName = file.name.replaceAll(RegExp(r'\.[^/.]+$'), '');
          _soundId = 'custom';
        });
        await widget.onPreviewAudio(_buildItem());
      }
    }
  }

  ReminderItem _buildItem() {
    final cleanTitle = _titleController.text.trim();
    return ReminderItem(
      id: widget.initialItem.id,
      title: cleanTitle.isEmpty ? 'Reminder' : cleanTitle,
      time24: _time24,
      repeat: _repeat,
      soundId: _soundId,
      customAudioPath: _customAudioPath,
      customAudioName: _customAudioName,
      enabled: true,
      snoozeCount: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = widget.isDark ? const Color(0xFF9E9EA8) : const Color(0xFF6B6A66);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.isNew ? 'New Reminder' : 'Edit Reminder',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          _SectionLabel('Reminder', color: muted),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              hintText: 'e.g. Take evening walk',
              filled: true,
              fillColor: theme.colorScheme.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 18),
          _SectionLabel('Time', color: muted),
          OutlinedButton(
            onPressed: _pickTime,
            style: OutlinedButton.styleFrom(
              backgroundColor: theme.colorScheme.surface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _time24,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _SectionLabel('Repeat', color: muted),
          Wrap(
            spacing: 8,
            children: ['Once', 'Daily', 'Weekdays'].map((option) {
              return ChoiceChip(
                label: Text(option),
                selected: _repeat == option,
                onSelected: (_) => setState(() => _repeat = option),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          _SectionLabel('Alarm Sound', color: muted),
          ...kBuiltInSounds.map((s) {
            final selected = _soundId == s.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                tileColor: theme.colorScheme.surface,
                selected: selected,
                title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.play_arrow_rounded),
                onTap: () => setState(() => _soundId = s.id),
              ),
            );
          }),
          if (_customAudioName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                tileColor: theme.colorScheme.surface,
                selected: _soundId == 'custom',
                title: Text(
                  'Custom: $_customAudioName',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: const Icon(Icons.play_arrow_rounded),
                onTap: () async {
                  setState(() => _soundId = 'custom');
                  await widget.onPreviewAudio(_buildItem());
                },
              ),
            ),
          OutlinedButton.icon(
            onPressed: _pickAudioFile,
            icon: const Icon(Icons.audio_file_rounded),
            label: const Text('Choose audio / music from phone'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 18),
          _SectionLabel('Backdrop', color: muted),
          Wrap(
            spacing: 8,
            children: [
              _backdropChip('Clean', BackdropStyle.clean),
              _backdropChip('Soft Grid', BackdropStyle.grid),
              _backdropChip('Ambient Drift', BackdropStyle.drift),
            ],
          ),
          const SizedBox(height: 26),
          Row(
            children: [
              if (!widget.isNew) ...[
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(const _EditorResult(deleted: true)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_EditorResult(savedItem: _buildItem())),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _backdropChip(String label, BackdropStyle style) {
    return ChoiceChip(
      label: Text(label),
      selected: _currentBackdrop == style,
      onSelected: (_) async {
        setState(() => _currentBackdrop = style);
        await widget.onSelectBackdrop(style);
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;

  const _SectionLabel(this.text, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
    );
  }
}

class AlarmTakeoverScreen extends StatelessWidget {
  final ReminderItem reminder;
  final bool isDark;
  final VoidCallback onSnooze;
  final VoidCallback onDismiss;

  const AlarmTakeoverScreen({
    super.key,
    required this.reminder,
    required this.isDark,
    required this.onSnooze,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = isDark ? const Color(0xFF141210) : const Color(0xFFFFFBEB);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          child: Column(
            children: [
              Text(
                reminder.time24,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: theme.colorScheme.primary,
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    reminder.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w700,
                      height: 1.08,
                      letterSpacing: -1.0,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onSnooze,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: theme.colorScheme.surface,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text(
                        'Snooze 5m',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: onDismiss,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text(
                        'Dismiss',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
