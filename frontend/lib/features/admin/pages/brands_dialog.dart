import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_image.dart';
import '../data/admin_data.dart';
import '../widgets/photo_field.dart';

Future<void> showBrandsManager(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _BrandsManager());

class _BrandsManager extends ConsumerStatefulWidget {
  const _BrandsManager();

  @override
  ConsumerState<_BrandsManager> createState() => _BrandsManagerState();
}

class _BrandsManagerState extends ConsumerState<_BrandsManager> {
  @override
  void initState() {
    super.initState();
    // фирмы могли прийти с товарами из Excel — показываем свежий список
    Future.microtask(ref.read(brandsProvider.notifier).reload);
  }

  Future<void> _edit(AdminBrand? b) => showDialog<void>(
    context: context,
    builder: (_) => _BrandEditor(brand: b),
  );

  Future<void> _delete(AdminBrand b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Удалить «${b.name}»?'),
        content: Text(
          b.productsCount == 0
              ? 'Фирма пропадёт из списка.'
              : 'У ${b.productsCount} товаров поле «Производитель» станет пустым. Сами товары останутся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.lowStock),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(brandsProvider.notifier).delete(b.id!);
  }

  @override
  Widget build(BuildContext context) {
    final brands = ref.watch(brandsProvider);
    final muted = TextStyle(color: context.palette.textSecondary, fontSize: 13);
    return AlertDialog(
      title: const Text('Фирмы'),
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Производители товаров: по ним покупатели фильтруют каталог. '
              'Переименование меняет фирму сразу у всех её товаров.',
              style: muted,
            ),
            const SizedBox(height: Insets.md),
            Expanded(
              child: brands.isEmpty
                  ? const Center(child: Text('Фирм пока нет'))
                  : ListView.separated(
                      itemCount: brands.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final b = brands[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 22,
                            backgroundColor: AppColors.brand.withValues(
                              alpha: 0.1,
                            ),
                            child: b.logoUrl == null
                                ? Text(
                                    b.name.characters.first.toUpperCase(),
                                    style: const TextStyle(
                                      color: AppColors.brand,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  )
                                : ClipOval(
                                    child: SizedBox.square(
                                      dimension: 44,
                                      child: AppImage(
                                        imageUrl: b.logoUrl!,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                          ),
                          title: Text(b.name),
                          subtitle: Text(
                            b.id == null
                                ? '${b.productsCount} тов. · из Excel, не в списке'
                                : '${b.productsCount} тов.',
                            style: muted,
                          ),
                          trailing: b.id == null
                              ? TextButton(
                                  onPressed: () =>
                                      ref.read(brandsProvider.notifier).save(b),
                                  child: const Text('В список'),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Изменить',
                                      onPressed: () => _edit(b),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      tooltip: 'Удалить',
                                      onPressed: () => _delete(b),
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                          onTap: b.id == null ? null : () => _edit(b),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _edit(null),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Новая фирма'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Готово'),
        ),
      ],
    );
  }
}

class _BrandEditor extends ConsumerStatefulWidget {
  const _BrandEditor({this.brand});
  final AdminBrand? brand;

  @override
  ConsumerState<_BrandEditor> createState() => _BrandEditorState();
}

class _BrandEditorState extends ConsumerState<_BrandEditor> {
  late final _name = TextEditingController(text: widget.brand?.name);
  late String? _logo = widget.brand?.logoUrl;
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
    final ok = await ref
        .read(brandsProvider.notifier)
        .save(
          AdminBrand(
            id: widget.brand?.id,
            name: name,
            logoUrl: _logo,
            productsCount: widget.brand?.productsCount ?? 0,
          ),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.brand == null ? 'Новая фирма' : 'Фирма'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: widget.brand == null,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Название',
              hintText: 'Например, «Ферма Иванова»',
            ),
          ),
          const SizedBox(height: Insets.sm),
          PhotoField(
            value: _logo,
            hint: 'Логотип — квадратный, PNG или JPG',
            onChanged: (v) => setState(() => _logo = v),
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
