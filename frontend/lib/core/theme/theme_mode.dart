import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences подставляется в main() через override (их нужно загрузить асинхронно до runApp).
/// В тестах — null: тема просто не сохраняется.
final sharedPrefsProvider = Provider<SharedPreferences?>((ref) => null);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    final saved = ref.watch(sharedPrefsProvider)?.getString(_key);
    return ThemeMode.values.where((m) => m.name == saved).firstOrNull ??
        ThemeMode.system;
  }

  void set(ThemeMode mode) {
    state = mode;
    ref.read(sharedPrefsProvider)?.setString(_key, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

extension ThemeModeUi on ThemeMode {
  String get label => switch (this) {
    ThemeMode.light => 'Светлая',
    ThemeMode.dark => 'Тёмная',
    ThemeMode.system => 'Как в системе',
  };

  IconData get icon => switch (this) {
    ThemeMode.light => Icons.light_mode_outlined,
    ThemeMode.dark => Icons.dark_mode_outlined,
    ThemeMode.system => Icons.brightness_auto_outlined,
  };
}

class ThemeModeButton extends ConsumerWidget {
  const ThemeModeButton({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    // Иконка показывает фактическую тему, а не настройку: «system» → солнце/луна по системе
    final dark = Theme.of(context).brightness == Brightness.dark;
    return PopupMenuButton<ThemeMode>(
      tooltip: 'Тема: ${mode.label}',
      initialValue: mode,
      onSelected: ref.read(themeModeProvider.notifier).set,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (c, a) => RotationTransition(
          turns: Tween(begin: 0.75, end: 1.0).animate(a),
          child: c,
        ),
        child: Icon(
          dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
          key: ValueKey(dark),
          color: color,
        ),
      ),
      itemBuilder: (_) => [
        for (final m in ThemeMode.values)
          PopupMenuItem(
            value: m,
            child: Row(
              children: [
                Icon(m.icon, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(m.label)),
                if (m == mode) const Icon(Icons.check_rounded, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}

class ThemeModeSelector extends ConsumerWidget {
  const ThemeModeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return SegmentedButton<ThemeMode>(
      showSelectedIcon: false,
      segments: [
        for (final m in [ThemeMode.light, ThemeMode.dark, ThemeMode.system])
          ButtonSegment(
            value: m,
            icon: Icon(m.icon, size: 18),
            label: Text(m.label),
          ),
      ],
      selected: {mode},
      onSelectionChanged: (s) =>
          ref.read(themeModeProvider.notifier).set(s.first),
    );
  }
}
