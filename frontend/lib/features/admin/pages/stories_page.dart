import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_image.dart';
import '../data/admin_data.dart';
import '../data/admin_repository.dart';
import '../widgets/admin_widgets.dart';

final _date = DateFormat('d MMM', 'ru');

class StoriesPage extends ConsumerWidget {
  const StoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stories = ref.watch(storiesProvider);
    final n = ref.read(storiesProvider.notifier);
    final palette = context.palette;
    return ListView(
      padding: const EdgeInsets.all(Insets.xl),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Кружочки показываются вверху главной страницы сайта в этом порядке. '
                'В каждой истории — от 1 до 10 слайдов с картинкой, текстом и кнопкой.',
                style: TextStyle(color: palette.textSecondary),
              ),
            ),
            const SizedBox(width: Insets.lg),
            FilledButton.icon(
              onPressed: () => showStoryEditor(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Новая история'),
            ),
          ],
        ),
        const SizedBox(height: Insets.lg),
        if (stories.isNotEmpty)
          AdminCard(
            title: 'Так это выглядит на сайте',
            child: SizedBox(
              height: 120, // кружок 72 + подпись в две строки
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final s in stories.where((s) => s.isLive))
                    Padding(
                      padding: const EdgeInsets.only(right: Insets.md),
                      child: StoryCircle(story: s),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: Insets.lg),
        if (stories.isEmpty)
          const AdminCard(
            child: EmptyState(
              icon: Icons.amp_stories_outlined,
              title: 'Историй пока нет',
              subtitle: 'Добавьте первую: акция, новинка, рецепт или новость магазина',
            ),
          ),
        for (final (i, s) in stories.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.md),
            child: AdminCard(
              padding: const EdgeInsets.all(Insets.md),
              child: Row(
                children: [
                  Column(
                    children: [
                      IconButton(
                        tooltip: 'Левее',
                        onPressed: i == 0 ? null : () => n.move(s, -1),
                        icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Правее',
                        onPressed: i == stories.length - 1
                            ? null
                            : () => n.move(s, 1),
                        icon: const Icon(
                          Icons.arrow_downward_rounded,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                  StoryCircle(story: s, size: 56, showTitle: false),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          [
                            '${s.slides.length} ${s.slides.length == 1 ? 'слайд' : (s.slides.length < 5 ? 'слайда' : 'слайдов')}',
                            if (s.startsAt != null)
                              'с ${_date.format(s.startsAt!)}',
                            if (s.endsAt != null)
                              'до ${_date.format(s.endsAt!)}',
                            if (!s.isActive)
                              'выключена'
                            else if (!s.isLive)
                              'вне сроков показа',
                          ].join(' · '),
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: s.isActive ? 'Показывается' : 'Скрыта',
                    child: Switch(
                      value: s.isActive,
                      onChanged: (_) => n.toggle(s),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Изменить',
                    onPressed: () => showStoryEditor(context, ref, s),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Удалить',
                    color: AppColors.lowStock,
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: Text('Удалить историю «${s.title}»?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Отмена'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.lowStock,
                              ),
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Удалить'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) await n.delete(s);
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class StoryCircle extends StatelessWidget {
  const StoryCircle({
    super.key,
    required this.story,
    this.size = 72,
    this.showTitle = true,
  });
  final AdminStory story;
  final double size;
  final bool showTitle;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size + 12,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [story.color, AppColors.hit, story.color],
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.alphaBlend(
                story.color.withValues(alpha: 0.18),
                context.palette.surface,
              ),
              border: Border.all(color: context.palette.surface, width: 2),
            ),
            padding: EdgeInsets.all(size * 0.14),
            child: story.coverUrl.isEmpty
                ? Icon(
                    Icons.image_outlined,
                    color: context.palette.textSecondary,
                  )
                : AppImage(imageUrl: story.coverUrl, fit: BoxFit.contain),
          ),
        ),
        if (showTitle) ...[
          const SizedBox(height: 4),
          Text(
            story.title,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    ),
  );
}

Future<void> showStoryEditor(
  BuildContext context,
  WidgetRef ref, [
  AdminStory? story,
]) => showDialog<void>(
  context: context,
  builder: (_) => _StoryEditor(story: story),
);

class _SlideDraft {
  _SlideDraft([StorySlideData? s])
    : image = s?.imageUrl,
      headline = TextEditingController(text: s?.headline),
      caption = TextEditingController(text: s?.caption),
      ctaLabel = TextEditingController(text: s?.ctaLabel),
      ctaUrl = TextEditingController(text: s?.ctaUrl);
  String? image;
  final TextEditingController headline, caption, ctaLabel, ctaUrl;

  void dispose() {
    for (final c in [headline, caption, ctaLabel, ctaUrl]) {
      c.dispose();
    }
  }
}

class _StoryEditor extends ConsumerStatefulWidget {
  const _StoryEditor({this.story});
  final AdminStory? story;

  @override
  ConsumerState<_StoryEditor> createState() => _StoryEditorState();
}

class _StoryEditorState extends ConsumerState<_StoryEditor> {
  static const _colors = [
    Color(0xFFE11D48),
    Color(0xFFF97316),
    Color(0xFFD97706),
    Color(0xFF16A34A),
    Color(0xFF0891B2),
    AppColors.brand,
    AppColors.accent,
    AppColors.cta,
    Color(0xFF334155),
  ];
  final _form = GlobalKey<FormState>();
  late final s = widget.story;
  late final _title = TextEditingController(text: s?.title);
  late String? _cover = s?.coverUrl;
  late Color _color = s?.color ?? _colors[5];
  late bool _active = s?.isActive ?? true;
  late DateTime? _from = s?.startsAt, _to = s?.endsAt;
  late final List<_SlideDraft> _slides = [
    for (final x in s?.slides ?? const <StorySlideData>[]) _SlideDraft(x),
    if ((s?.slides ?? const []).isEmpty) _SlideDraft(),
  ];
  String? _uploading; // 'cover' или индекс слайда
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    for (final d in _slides) {
      d.dispose();
    }
    super.dispose();
  }

  Future<String?> _upload(String key) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    final f = files.singleOrNull;
    if (f == null) return null;
    setState(() {
      _uploading = key;
      _error = null;
    });
    try {
      final bytes = await f.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) throw 'Файл больше 10 МБ';
      return await ref
          .read(adminRepositoryProvider)
          .uploadProductImage(f.name, bytes);
    } catch (e) {
      setState(() => _error = '$e');
      return null;
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<void> _pickDate(bool from) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (d == null) return;
    setState(() {
      if (from) {
        _from = d;
      } else {
        _to = DateTime(d.year, d.month, d.day, 23, 59);
      }
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_cover == null) {
      return setState(() => _error = 'Загрузите обложку кружка');
    }
    if (_slides.any((d) => d.image == null)) {
      return setState(() => _error = 'У каждого слайда должна быть картинка');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    String? opt(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final ok = await ref
        .read(storiesProvider.notifier)
        .save(
          AdminStory(
            id: s?.id ?? 0,
            title: _title.text.trim(),
            coverUrl: _cover!,
            color: _color,
            isActive: _active,
            startsAt: _from,
            endsAt: _to,
            slides: [
              for (final d in _slides)
                StorySlideData(
                  imageUrl: d.image!,
                  headline: d.headline.text.trim(),
                  caption: opt(d.caption),
                  ctaLabel: opt(d.ctaLabel),
                  ctaUrl: opt(d.ctaUrl),
                ),
            ],
          ),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final categories = ref.watch(adminCategoriesProvider);
    Widget imageBox(
      String? url,
      String key,
      VoidCallback onPick, {
      double size = 88,
    }) => InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: _uploading == null ? onPick : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            _color.withValues(alpha: 0.15),
            palette.surface,
          ),
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: palette.border),
        ),
        padding: const EdgeInsets.all(8),
        child: _uploading == key
            ? const Center(child: CircularProgressIndicator())
            : url == null
            ? Icon(
                Icons.add_photo_alternate_outlined,
                color: palette.textSecondary,
              )
            : AppImage(imageUrl: url, fit: BoxFit.contain),
      ),
    );

    return AlertDialog(
      title: Text(s == null ? 'Новая история' : 'История «${s!.title}»'),
      content: SizedBox(
        width: 640,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        imageBox(_cover, 'cover', () async {
                          final url = await _upload('cover');
                          if (url != null) setState(() => _cover = url);
                        }),
                        const SizedBox(height: 4),
                        Text(
                          'Обложка',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: Insets.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _title,
                            maxLength: 40,
                            decoration: const InputDecoration(
                              labelText: 'Подпись под кружком',
                              hintText: 'Сезон ягод',
                            ),
                            validator: (v) => (v ?? '').trim().isEmpty
                                ? 'Укажите подпись'
                                : null,
                          ),
                          Wrap(
                            spacing: 6,
                            children: [
                              for (final c in _colors)
                                GestureDetector(
                                  onTap: () => setState(() => _color = c),
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: c,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: c == _color
                                            ? palette.textPrimary
                                            : Colors.transparent,
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Insets.md),
                Wrap(
                  spacing: Insets.sm,
                  runSpacing: Insets.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      label: Text(_active ? 'Показывать' : 'Скрыта'),
                      selected: _active,
                      onSelected: (v) => setState(() => _active = v),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.event_outlined, size: 16),
                      label: Text(
                        _from == null
                            ? 'Показывать с…'
                            : 'С ${_date.format(_from!)}',
                      ),
                      onPressed: () => _pickDate(true),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.event_busy_outlined, size: 16),
                      label: Text(
                        _to == null
                            ? '…и до (необязательно)'
                            : 'До ${_date.format(_to!)}',
                      ),
                      onPressed: () => _pickDate(false),
                    ),
                    if (_from != null || _to != null)
                      TextButton(
                        onPressed: () => setState(() => _from = _to = null),
                        child: const Text('Без сроков'),
                      ),
                  ],
                ),
                const Divider(height: Insets.xl * 2),
                Text('Слайды', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: Insets.sm),
                for (final (i, d) in _slides.indexed)
                  Container(
                    margin: const EdgeInsets.only(bottom: Insets.md),
                    padding: const EdgeInsets.all(Insets.md),
                    decoration: BoxDecoration(
                      border: Border.all(color: palette.border),
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            imageBox(d.image, 'slide$i', () async {
                              final url = await _upload('slide$i');
                              if (url != null) setState(() => d.image = url);
                            }),
                            Text(
                              '${i + 1}',
                              style: TextStyle(color: palette.textSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(width: Insets.md),
                        Expanded(
                          child: Column(
                            children: [
                              TextFormField(
                                controller: d.headline,
                                maxLength: 120,
                                decoration: const InputDecoration(
                                  labelText: 'Заголовок',
                                  isDense: true,
                                ),
                                validator: (v) => (v ?? '').trim().isEmpty
                                    ? 'Укажите заголовок'
                                    : null,
                              ),
                              TextFormField(
                                controller: d.caption,
                                maxLength: 300,
                                decoration: const InputDecoration(
                                  labelText: 'Подпись (необязательно)',
                                  isDense: true,
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: d.ctaLabel,
                                      maxLength: 40,
                                      decoration: const InputDecoration(
                                        labelText: 'Текст кнопки',
                                        isDense: true,
                                      ),
                                      validator: (v) =>
                                          (v ?? '').trim().isEmpty !=
                                              d.ctaUrl.text.trim().isEmpty
                                          ? 'Нужны и текст, и ссылка'
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: Insets.sm),
                                  Expanded(
                                    child: TextFormField(
                                      controller: d.ctaUrl,
                                      maxLength: 300,
                                      decoration: InputDecoration(
                                        labelText: 'Ссылка',
                                        hintText: '/catalog/…',
                                        isDense: true,
                                        suffixIcon: PopupMenuButton<String>(
                                          tooltip: 'Выбрать категорию',
                                          icon: const Icon(
                                            Icons.category_outlined,
                                            size: 18,
                                          ),
                                          itemBuilder: (_) => [
                                            for (final c in categories)
                                              PopupMenuItem(
                                                value: c.url,
                                                child: Text(c.name),
                                              ),
                                          ],
                                          onSelected: (v) => setState(() {
                                            d.ctaUrl.text = v;
                                            if (d.ctaLabel.text
                                                .trim()
                                                .isEmpty) {
                                              d.ctaLabel.text = 'Смотреть';
                                            }
                                          }),
                                        ),
                                      ),
                                      validator: (v) {
                                        final t = (v ?? '').trim();
                                        if (t.isEmpty) return null;
                                        return RegExp(
                                              r'^(/($|[^/\\])|https://)',
                                            ).hasMatch(t)
                                            ? null
                                            : 'Путь сайта (/catalog/…) или https://';
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Column(
                          children: [
                            IconButton(
                              tooltip: 'Выше',
                              onPressed: i == 0
                                  ? null
                                  : () => setState(
                                      () => _slides.insert(
                                        i - 1,
                                        _slides.removeAt(i),
                                      ),
                                    ),
                              icon: const Icon(
                                Icons.arrow_upward_rounded,
                                size: 18,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Удалить слайд',
                              onPressed: _slides.length == 1
                                  ? null
                                  : () => setState(
                                      () => _slides.removeAt(i).dispose(),
                                    ),
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (_slides.length < 10)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _slides.add(_SlideDraft())),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Добавить слайд'),
                  ),
                const SizedBox(height: Insets.sm),
                Text(
                  'Картинки: JPG, PNG или WebP, лучше квадрат от 800×800 px, продукт на прозрачном или белом фоне — '
                  'фон слайда закрасится выбранным цветом.',
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
                if (_error != null) ...[
                  const SizedBox(height: Insets.sm),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.lowStock),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _busy || _uploading != null ? null : _save,
          child: Text(s == null ? 'Создать' : 'Сохранить'),
        ),
      ],
    );
  }
}
