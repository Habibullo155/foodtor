import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_image.dart';
import '../data/admin_data.dart' hide slugify;
import '../widgets/photo_field.dart';
import 'catalog_pages.dart' show slugify;

Future<void> showCategoriesManager(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _CategoriesManager(),
);

class _CategoriesManager extends ConsumerWidget {
  const _CategoriesManager();

  Future<void> _edit(BuildContext context, AdminCategory? c) =>
      showDialog<void>(
        context: context,
        builder: (_) => _CategoryEditor(category: c),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(adminCategoriesProvider);
    final muted = TextStyle(color: context.palette.textSecondary, fontSize: 13);
    return AlertDialog(
      title: const Text('Категории'),
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Фото категории показывается в круглой плитке на главной сайта. Лучше квадратное, на светлом или прозрачном фоне.',
              style: muted,
            ),
            const SizedBox(height: Insets.md),
            Expanded(
              child: cats.isEmpty
                  ? const Center(child: Text('Категорий пока нет'))
                  : ListView.separated(
                      itemCount: cats.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final c = cats[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 22,
                            backgroundColor: context.palette.surfaceMuted,
                            child: c.imageUrl == null
                                ? Icon(
                                    Icons.image_outlined,
                                    color: context.palette.textSecondary,
                                  )
                                : ClipOval(
                                    child: SizedBox.square(
                                      dimension: 44,
                                      child: AppImage(
                                        imageUrl: c.imageUrl!,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                          ),
                          title: Text(c.name),
                          subtitle: Text(
                            c.imageUrl == null ? 'Без фото' : c.url,
                            style: muted,
                          ),
                          trailing: IconButton(
                            tooltip: 'Изменить',
                            onPressed: () => _edit(context, c),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          onTap: () => _edit(context, c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _edit(context, null),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Новая категория'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Готово'),
        ),
      ],
    );
  }
}

class _CategoryEditor extends ConsumerStatefulWidget {
  const _CategoryEditor({this.category});
  final AdminCategory? category;

  @override
  ConsumerState<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends ConsumerState<_CategoryEditor> {
  late final _name = TextEditingController(text: widget.category?.name);
  late String? _photo = widget.category?.imageUrl;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final n = ref.read(adminCategoriesProvider.notifier);
    var c = widget.category;
    if (c == null) {
      c = await n.create(name, slugify(name));
      if (c == null) {
        setState(() => _busy = false);
        return;
      }
    }
    final ok = await n.save(
      c.copyWith(name: name, imageUrl: _photo, clearImage: _photo == null),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.category == null ? 'Новая категория' : 'Категория'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: widget.category == null,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Название',
              hintText: 'Например, «Молочные продукты»',
            ),
          ),
          const SizedBox(height: Insets.sm),
          PhotoField(
            value: _photo,
            onChanged: (v) => setState(() => _photo = v),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: const Text('Сохранить'),
      ),
    ],
  );
}
