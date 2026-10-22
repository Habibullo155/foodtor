import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_image.dart';
import '../auth/admin_auth.dart';
import '../data/admin_data.dart';
import '../data/admin_repository.dart';
import '../rbac.dart';
import '../widgets/admin_widgets.dart';

class _ProductQuery extends Notifier<(String, int?)> {
  @override
  (String, int?) build() => ('', null);
  void set(String q, int? cat) => state = (q, cat);
}

final _productQueryProvider = NotifierProvider<_ProductQuery, (String, int?)>(
  _ProductQuery.new,
);

class ProductsPage extends ConsumerWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (query, cat) = ref.watch(_productQueryProvider);
    final categories = ref.watch(adminCategoriesProvider);
    final perms = ref.watch(permissionsProvider);
    final canWrite = perms.contains(Permission.productsWrite);
    final canImport = perms.contains(Permission.productsImport);
    final items = ref
        .watch(adminProductsProvider)
        .where(
          (p) =>
              (cat == null || p.categoryId == cat) &&
              p.name.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();

    return ListView(
      padding: const EdgeInsets.all(Insets.xl),
      children: [
        Wrap(
          spacing: Insets.md,
          runSpacing: Insets.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 300,
              child: TextField(
                onChanged: (v) =>
                    ref.read(_productQueryProvider.notifier).set(v, cat),
                decoration: const InputDecoration(
                  hintText: 'Поиск по названию',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            DropdownMenu<int?>(
              initialSelection: cat,
              hintText: 'Все категории',
              width: 240,
              onSelected: (v) =>
                  ref.read(_productQueryProvider.notifier).set(query, v),
              dropdownMenuEntries: [
                const DropdownMenuEntry(value: null, label: 'Все категории'),
                for (final c in categories)
                  DropdownMenuEntry(value: c.id, label: c.name),
              ],
            ),
            if (canImport)
              OutlinedButton.icon(
                onPressed: () => _import(context, ref),
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Импорт .xlsx / .csv'),
              ),
            if (canWrite) ...[
              OutlinedButton.icon(
                onPressed: () => _newCategory(context, ref),
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Категория'),
              ),
              FilledButton.icon(
                onPressed: () => showProductEditor(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Новый товар'),
              ),
            ],
          ],
        ),
        if (canWrite && items.isNotEmpty) ...[
          const SizedBox(height: Insets.md),
          Row(
            children: [
              Icon(
                Icons.edit_outlined,
                size: 16,
                color: context.palette.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Нажмите на товар или ✎, чтобы изменить название, цену, себестоимость, остаток, фото или скрыть его',
                  style: TextStyle(
                    color: context.palette.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: Insets.lg),
        AdminCard(
          padding: EdgeInsets.zero,
          child: items.isEmpty
              ? const EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Товаров пока нет',
                  subtitle:
                      'Добавьте первый товар или загрузите каталог из Excel',
                )
              : LayoutBuilder(
                  builder: (context, c) => c.maxWidth >= 860
                      ? _ProductsTable(items: items, canWrite: canWrite)
                      : _ProductsList(items: items, canWrite: canWrite),
                ),
        ),
      ],
    );
  }

  static Future<void> _import(BuildContext context, WidgetRef ref) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv'],
    );
    final file = files.singleOrNull;
    if (file == null) return; // пользователь закрыл диалог
    final bytes = await file
        .readAsBytes(); // в вебе пути к файлу нет — читаем содержимое
    final report = await ref
        .read(adminProductsProvider.notifier)
        .import(file.name, bytes);
    if (report != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(report)));
    }
  }

  static Future<void> _newCategory(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Новая категория'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Название',
            hintText: 'Например, «Молочные продукты»',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final c = await ref
          .read(adminCategoriesProvider.notifier)
          .create(name.text.trim(), slugify(name.text));
      if (c != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Категория «${c.name}» создана')),
        );
      }
    }
  }
}

/// Транслитерация для slug: «Молочные продукты» → «molochnye-produkty-7f3».
String slugify(String name) {
  const map = {
    'а': 'a',
    'б': 'b',
    'в': 'v',
    'г': 'g',
    'д': 'd',
    'е': 'e',
    'ё': 'e',
    'ж': 'zh',
    'з': 'z',
    'и': 'i',
    'й': 'y',
    'к': 'k',
    'л': 'l',
    'м': 'm',
    'н': 'n',
    'о': 'o',
    'п': 'p',
    'р': 'r',
    'с': 's',
    'т': 't',
    'у': 'u',
    'ф': 'f',
    'х': 'h',
    'ц': 'ts',
    'ч': 'ch',
    'ш': 'sh',
    'щ': 'sch',
    'ъ': '',
    'ы': 'y',
    'ь': '',
    'э': 'e',
    'ю': 'yu',
    'я': 'ya',
  };
  final base = name
      .toLowerCase()
      .split('')
      .map((c) => map[c] ?? c)
      .join()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  final suffix = Random().nextInt(0xfff).toRadixString(16);
  return '${base.replaceAll(RegExp(r'^-+|-+$'), '')}-$suffix';
}

Future<void> showProductEditor(
  BuildContext context,
  WidgetRef ref, [
  AdminProduct? product,
]) => showDialog<void>(
  context: context,
  builder: (_) => _ProductEditor(product: product),
);

class _ProductEditor extends ConsumerStatefulWidget {
  const _ProductEditor({this.product});
  final AdminProduct? product;

  @override
  ConsumerState<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends ConsumerState<_ProductEditor> {
  final _form = GlobalKey<FormState>();
  late final AdminProduct? p = widget.product;
  late final _name = TextEditingController(text: p?.name);
  late final _sku = TextEditingController(
    text: p?.sku ?? 'GR-${DateTime.now().millisecondsSinceEpoch % 100000}',
  );
  late final _brand = TextEditingController(text: p?.brand);
  late final _unit = TextEditingController(text: p?.unit);
  late final _cost = TextEditingController(text: p?.cost.toStringAsFixed(0));
  late final _price = TextEditingController(text: p?.price.toStringAsFixed(0));
  late final _wholesale = TextEditingController(
    text: p?.wholesalePrice?.toStringAsFixed(0),
  );
  late final _stock = TextEditingController(text: '${p?.stock ?? 0}');
  late final _image = TextEditingController(
    text: (p?.imageUrl ?? '').startsWith('http') ? p!.imageUrl : null,
  );
  late int? _category = p?.categoryId;
  late bool _hit = p?.isHit ?? false;
  late bool _active = p?.isActive ?? true;
  bool _busy = false;
  late String? _photo =
      p?.imageUrl; // текущее фото: загруженное, ссылка или демо-ассет
  bool _uploading = false;
  String? _photoError;

  /// Фото с компьютера: проверяем размер ещё до отправки, сервер проверит ещё раз и пересохранит.
  Future<void> _pickPhoto() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    final file = files.singleOrNull;
    if (file == null) return;
    setState(() {
      _uploading = true;
      _photoError = null;
    });
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        throw 'Файл больше 10 МБ — уменьшите фото';
      }
      final img = await decodeImageFromList(bytes);
      final (w, h) = (img.width, img.height);
      img.dispose();
      if (w < 300 || h < 300) {
        throw 'Фото слишком маленькое ($w×$h). Нужно от 300×300 px, лучше 1000×1000';
      }
      final url = await ref
          .read(adminRepositoryProvider)
          .uploadProductImage(file.name, bytes);
      setState(() {
        _photo = url;
        _image.clear();
      });
    } catch (e) {
      setState(() => _photoError = '$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  double? _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.').replaceAll(' ', ''));

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await ref
        .read(adminProductsProvider.notifier)
        .save(
          AdminProduct(
            id: p?.id ?? 0,
            sku: _sku.text.trim(),
            name: _name.text.trim(),
            unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
            brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
            imageUrl: _image.text.trim().isEmpty ? _photo : _image.text.trim(),
            categoryId: _category,
            cost: _num(_cost)!,
            price: _num(_price)!,
            wholesalePrice: _num(_wholesale),
            stock: int.parse(_stock.text),
            isHit: _hit,
            isActive: _active,
            description: p?.description ?? '',
          ),
          isNew: p == null,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  String _wholesaleHint(double price) {
    final w = _num(_wholesale);
    if (w == null) {
      return 'Пусто — оптовики покупают по розничной цене';
    }
    if (price <= 0 || w >= price) return 'Видят только подтверждённые оптовики';
    return 'Скидка для оптовиков ${((1 - w / price) * 100).round()}% · видят только они';
  }

  @override
  Widget build(BuildContext context) {
    final cost = _num(_cost) ?? 0, price = _num(_price) ?? 0;
    final margin = price == 0 ? 0.0 : (price - cost) / price * 100;
    final categories = ref.watch(adminCategoriesProvider);
    String? required(String? v) =>
        (v ?? '').trim().isEmpty ? 'Обязательное поле' : null;
    String? number(String? v) =>
        double.tryParse((v ?? '').replaceAll(',', '.')) == null
        ? 'Число'
        : null;

    return AlertDialog(
      title: Text(p == null ? 'Новый товар' : 'Редактирование'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          onChanged: () => setState(() {}),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Название'),
                  validator: required,
                ),
                const SizedBox(height: Insets.md),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _sku,
                        enabled: p == null,
                        decoration: const InputDecoration(
                          labelText: 'Артикул (SKU)',
                        ),
                        validator: (v) =>
                            RegExp(r'^[A-Za-z0-9._\-]+$').hasMatch(v ?? '')
                            ? null
                            : 'Латиница, цифры, - _ .',
                      ),
                    ),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: TextFormField(
                        controller: _unit,
                        decoration: const InputDecoration(
                          labelText: 'Фасовка',
                          hintText: '1 кг',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Insets.md),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _brand,
                        decoration: const InputDecoration(
                          labelText: 'Производитель',
                        ),
                      ),
                    ),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        isExpanded: true,
                        initialValue: _category,
                        decoration: const InputDecoration(
                          labelText: 'Категория',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Без категории'),
                          ),
                          for (final c in categories)
                            DropdownMenuItem(
                              value: c.id,
                              child: Text(
                                c.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _category = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Insets.md),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cost,
                        onTap: () => _selectAll(_cost),
                        decoration: const InputDecoration(
                          labelText: 'Себестоимость, ₽',
                        ),
                        validator: number,
                      ),
                    ),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: TextFormField(
                        controller: _price,
                        onTap: () => _selectAll(_price),
                        decoration: const InputDecoration(labelText: 'Цена, ₽'),
                        validator: number,
                      ),
                    ),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: TextFormField(
                        controller: _stock,
                        onTap: () => _selectAll(_stock),
                        decoration: const InputDecoration(labelText: 'Остаток'),
                        validator: (v) =>
                            int.tryParse(v ?? '') == null ? 'Целое' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Insets.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    price == 0
                        ? 'Укажите цену'
                        : 'Маржа: ${margin.toStringAsFixed(1)}%${margin < 0 ? ' — продажа в минус!' : ''}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _marginColor(margin),
                    ),
                  ),
                ),
                const SizedBox(height: Insets.md),
                TextFormField(
                  controller: _wholesale,
                  onTap: () => _selectAll(_wholesale),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Оптовая цена, ₽',
                    helperText: _wholesaleHint(price),
                    prefixIcon: const Icon(Icons.storefront_outlined),
                  ),
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) return null;
                    final w = double.tryParse(v!.replaceAll(',', '.'));
                    if (w == null || w <= 0) return 'Число больше нуля';
                    if (w >= price) return 'Должна быть ниже розничной';
                    return null;
                  },
                ),
                const SizedBox(height: Insets.md),
                _PhotoPicker(
                  url: _photo,
                  busy: _uploading,
                  error: _photoError,
                  onPick: _pickPhoto,
                  onRemove: _photo == null
                      ? null
                      : () => setState(() {
                          _photo = null;
                          _image.clear();
                        }),
                ),
                const SizedBox(height: Insets.sm),
                TextFormField(
                  controller: _image,
                  onChanged: (v) => setState(
                    () => _photo = v.trim().isEmpty ? _photo : v.trim(),
                  ),
                  decoration: const InputDecoration(
                    labelText: 'или ссылка на фото (https://…)',
                    isDense: true,
                  ),
                  validator: (v) =>
                      (v ?? '').isEmpty || (v ?? '').startsWith('https://')
                      ? null
                      : 'Ссылка должна начинаться с https://',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Бейдж «Хит»'),
                  value: _hit,
                  onChanged: (v) => setState(() => _hit = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Показывать в магазине'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
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
          onPressed: _busy ? null : _save,
          child: Text(p == null ? 'Создать' : 'Сохранить'),
        ),
      ],
    );
  }
}

Color _marginColor(double m) =>
    m >= 40 ? AppColors.fresh : (m >= 25 ? AppColors.hit : AppColors.lowStock);

class _StockPill extends StatelessWidget {
  const _StockPill(this.stock);
  final int stock;

  @override
  Widget build(BuildContext context) {
    final color = stock <= 5
        ? AppColors.lowStock
        : (stock <= 30 ? AppColors.hit : AppColors.fresh);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        '$stock шт.',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _ProductsTable extends ConsumerWidget {
  const _ProductsTable({required this.items, required this.canWrite});
  final List<AdminProduct> items;
  final bool canWrite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final head = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: context.palette.textSecondary,
      fontWeight: FontWeight.w600,
    );
    final cats = {
      for (final c in ref.watch(adminCategoriesProvider)) c.id: c.name,
    };
    Widget num(String s, {Color? color, bool bold = false}) => SizedBox(
      width: 100,
      child: Text(
        s,
        textAlign: TextAlign.right,
        style: TextStyle(
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.xl,
            vertical: Insets.md,
          ),
          decoration: BoxDecoration(
            color: context.palette.surfaceMuted,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(Radii.lg),
            ),
          ),
          child: Row(
            children: [
              Expanded(flex: 4, child: Text('ТОВАР', style: head)),
              Expanded(flex: 2, child: Text('КАТЕГОРИЯ', style: head)),
              SizedBox(
                width: 100,
                child: Text('СЕБЕСТ.', style: head, textAlign: TextAlign.right),
              ),
              SizedBox(
                width: 100,
                child: Text('ЦЕНА', style: head, textAlign: TextAlign.right),
              ),
              SizedBox(
                width: 100,
                child: Text('МАРЖА', style: head, textAlign: TextAlign.right),
              ),
              const SizedBox(width: Insets.xl),
              SizedBox(width: 90, child: Text('ОСТАТОК', style: head)),
              if (canWrite) const SizedBox(width: 48),
            ],
          ),
        ),
        for (final (i, item) in items.indexed) ...[
          if (i > 0) const Divider(),
          InkWell(
            onTap: canWrite
                ? () => showProductEditor(context, ref, item)
                : null,
            child: Opacity(
              opacity: item.isActive ? 1 : 0.5,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.xl,
                  vertical: Insets.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Row(
                        children: [
                          ProductThumb(item.imageUrl, size: 40),
                          const SizedBox(width: Insets.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  [
                                    item.sku,
                                    ?item.unit,
                                    ?item.brand,
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.palette.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        cats[item.categoryId] ?? '—',
                        style: TextStyle(color: context.palette.textSecondary),
                      ),
                    ),
                    num(money.format(item.cost)),
                    num(money.format(item.price), bold: true),
                    num(
                      '${item.marginPercent.toStringAsFixed(0)}%',
                      color: _marginColor(item.marginPercent),
                      bold: true,
                    ),
                    const SizedBox(width: Insets.xl),
                    SizedBox(
                      width: 90,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _StockPill(item.stock),
                      ),
                    ),
                    if (canWrite)
                      SizedBox(
                        width: 48,
                        child: IconButton(
                          tooltip: 'Изменить товар',
                          onPressed: () =>
                              showProductEditor(context, ref, item),
                          icon: const Icon(Icons.edit_outlined, size: 20),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ProductsList extends ConsumerWidget {
  const _ProductsList({required this.items, required this.canWrite});
  final List<AdminProduct> items;
  final bool canWrite;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    children: [
      for (final item in items)
        ListTile(
          onTap: canWrite ? () => showProductEditor(context, ref, item) : null,
          leading: ProductThumb(item.imageUrl, size: 44),
          title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${money.format(item.price)} · себест. ${money.format(item.cost)}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StockPill(item.stock),
              if (canWrite)
                IconButton(
                  tooltip: 'Изменить товар',
                  onPressed: () => showProductEditor(context, ref, item),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
            ],
          ),
        ),
    ],
  );
}

enum _RatingFilter {
  all('Все оценки'),
  high('★ 4–5'),
  mid('★ 3'),
  low('★ 1–2');

  const _RatingFilter(this.label);
  final String label;

  bool test(int r) => switch (this) {
    all => true,
    high => r >= 4,
    mid => r == 3,
    low => r <= 2,
  };
}

enum _ReviewSort {
  newest('Сначала новые'),
  lowFirst('Сначала низкие'),
  highFirst('Сначала высокие');

  const _ReviewSort(this.label);
  final String label;
}

class ReviewsPage extends ConsumerStatefulWidget {
  const ReviewsPage({super.key});

  @override
  ConsumerState<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends ConsumerState<ReviewsPage> {
  ReviewState? _status = ReviewState.pending; // null — все
  _RatingFilter _rating = _RatingFilter.all;
  _ReviewSort _sort = _ReviewSort.newest;
  String _query = '';
  final _selected = <int>{};

  List<AdminReview> _visible(List<AdminReview> all) {
    final q = _query.trim().toLowerCase();
    final list = [
      for (final r in all)
        if ((_status == null || r.state == _status) &&
            _rating.test(r.rating) &&
            (q.isEmpty ||
                r.text.toLowerCase().contains(q) ||
                r.productName.toLowerCase().contains(q) ||
                r.author.toLowerCase().contains(q)))
          r,
    ];
    final epoch = DateTime(2000);
    list.sort(
      (a, b) => switch (_sort) {
        _ReviewSort.newest => (b.createdAt ?? epoch).compareTo(
          a.createdAt ?? epoch,
        ),
        _ReviewSort.lowFirst => a.rating.compareTo(b.rating),
        _ReviewSort.highFirst => b.rating.compareTo(a.rating),
      },
    );
    return list;
  }

  Future<void> _bulk(Set<int> ids, ReviewState to) async {
    if (ids.isEmpty) return;
    if (to == ReviewState.rejected) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Отклонить ${ids.length} ${_plural(ids.length)}?'),
          content: const Text('Покупатели не увидят их на сайте.'),
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
              child: const Text('Отклонить'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await ref.read(reviewsProvider.notifier).moderateMany(ids, to);
    if (!mounted) return;
    setState(() => _selected.removeAll(ids));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${to == ReviewState.approved ? 'Опубликовано' : 'Отклонено'}: ${ids.length} ${_plural(ids.length)}',
        ),
      ),
    );
  }

  static String _plural(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'отзыв';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'отзыва';
    return 'отзывов';
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(reviewsProvider);
    final visible = _visible(all);
    final visibleIds = {for (final r in visible) r.id};
    _selected.retainAll({for (final r in all) r.id});
    final selectedVisible = _selected.intersection(visibleIds);
    final pendingHigh = {
      for (final r in all)
        if (r.state == ReviewState.pending && r.rating >= 4) r.id,
    };
    void toggleAll() => setState(() {
      if (selectedVisible.length == visible.length) {
        _selected.removeAll(visibleIds);
      } else {
        _selected.addAll(visibleIds);
      }
    });
    int count(ReviewState? s) =>
        s == null ? all.length : all.where((r) => r.state == s).length;
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(Insets.xl),
      children: [
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            for (final (s, label) in [
              (ReviewState.pending, 'На модерации'),
              (ReviewState.approved, 'Опубликованы'),
              (ReviewState.rejected, 'Отклонены'),
              (null, 'Все'),
            ])
              ChoiceChip(
                label: Text('$label · ${count(s)}'),
                selected: _status == s,
                onSelected: (_) => setState(() => _status = s),
              ),
          ],
        ),
        const SizedBox(height: Insets.md),
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final f in _RatingFilter.values)
              FilterChip(
                label: Text(f.label),
                selected: _rating == f,
                onSelected: (_) => setState(() => _rating = f),
              ),
            SizedBox(
              width: 260,
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Поиск по тексту, товару, автору',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            DropdownButton<_ReviewSort>(
              value: _sort,
              underline: const SizedBox.shrink(),
              items: [
                for (final s in _ReviewSort.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (v) => setState(() => _sort = v!),
            ),
          ],
        ),
        const SizedBox(height: Insets.lg),
        AdminCard(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.md,
            vertical: Insets.sm,
          ),
          child: Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(Radii.sm),
                onTap: visible.isEmpty ? null : toggleAll,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      tristate: true,
                      value: visible.isEmpty || selectedVisible.isEmpty
                          ? false
                          : (selectedVisible.length == visible.length
                                ? true
                                : null),
                      onChanged: visible.isEmpty ? null : (_) => toggleAll(),
                    ),
                    Text(
                      selectedVisible.isEmpty
                          ? 'Выбрать все (${visible.length})'
                          : 'Выбрано: ${selectedVisible.length}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: Insets.sm),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: selectedVisible.isEmpty
                    ? null
                    : () => _bulk(selectedVisible, ReviewState.approved),
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: const Text('Опубликовать выбранные'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.lowStock,
                ),
                onPressed: selectedVisible.isEmpty
                    ? null
                    : () => _bulk(selectedVisible, ReviewState.rejected),
                icon: const Icon(Icons.block_rounded, size: 18),
                label: const Text('Отклонить выбранные'),
              ),
              if (pendingHigh.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _bulk(pendingHigh, ReviewState.approved),
                  icon: const Icon(Icons.star_rounded, size: 18),
                  label: Text(
                    'Опубликовать все с оценкой 4–5 (${pendingHigh.length})',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Insets.lg),
        if (visible.isEmpty)
          AdminCard(
            child: EmptyState(
              icon: Icons.verified_outlined,
              title: all.isEmpty
                  ? 'Отзывов пока нет'
                  : 'Под фильтр ничего не попало',
              subtitle: all.isEmpty ? null : 'Измените статус или оценку',
            ),
          )
        else ...[
          Text(
            'Показано: ${visible.length}',
            style: text.bodySmall?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
          const SizedBox(height: Insets.sm),
          for (final r in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.md),
              child: _ReviewCard(
                review: r,
                selected: _selected.contains(r.id),
                onSelect: (v) => setState(
                  () => v ? _selected.add(r.id) : _selected.remove(r.id),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({
    required this.review,
    required this.selected,
    required this.onSelect,
  });
  final AdminReview review;
  final bool selected;
  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(reviewsProvider.notifier);
    final low = review.rating <= 2;
    return AdminCard(
      padding: const EdgeInsets.all(Insets.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(value: selected, onChanged: (v) => onSelect(v ?? false)),
          const SizedBox(width: Insets.xs),
          ProductThumb(review.productImage, size: 52),
          const SizedBox(width: Insets.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: Insets.sm,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      review.author,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 1; i <= 5; i++)
                          Icon(
                            i <= review.rating
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 16,
                            color: low
                                ? AppColors.lowStock
                                : const Color(0xFFFBBF24),
                          ),
                      ],
                    ),
                    Text(
                      'о «${review.productName}»',
                      style: TextStyle(color: context.palette.textSecondary),
                    ),
                    if (review.createdAt != null)
                      Text(
                        timeAgo(review.createdAt!),
                        style: TextStyle(
                          color: context.palette.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(review.text),
                const SizedBox(height: Insets.md),
                Wrap(
                  spacing: Insets.sm,
                  runSpacing: Insets.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (review.state == ReviewState.approved)
                      const Text(
                        '✓ Опубликован',
                        style: TextStyle(
                          color: AppColors.fresh,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (review.state == ReviewState.rejected)
                      const Text(
                        'Отклонён',
                        style: TextStyle(
                          color: AppColors.lowStock,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (review.state != ReviewState.approved)
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            n.moderate(review.id, ReviewState.approved),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Опубликовать'),
                      ),
                    if (review.state != ReviewState.rejected)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.lowStock,
                        ),
                        onPressed: () =>
                            n.moderate(review.id, ReviewState.rejected),
                        icon: const Icon(Icons.block_rounded, size: 18),
                        label: Text(
                          review.state == ReviewState.approved
                              ? 'Снять с публикации'
                              : 'Отклонить',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LoyaltyPage extends ConsumerWidget {
  const LoyaltyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final tiers = ref.watch(tiersProvider);
    return ListView(
      padding: const EdgeInsets.all(Insets.xl),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Статус клиента зависит от суммы доставленных заказов. Скидка уровня применяется к корзине автоматически (не действует на оптовые цены).',
                style: text.bodyMedium?.copyWith(
                  color: context.palette.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: Insets.lg),
            FilledButton.icon(
              onPressed: () => _addTier(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Уровень'),
            ),
          ],
        ),
        const SizedBox(height: Insets.lg),
        if (tiers.isEmpty)
          const AdminCard(
            child: EmptyState(
              icon: Icons.workspace_premium_outlined,
              title: 'Уровней пока нет',
              subtitle: 'Например: Bronze от 0 ₽ — 0%, Silver от 10 000 ₽ — 3%, Gold от 30 000 ₽ — 5%',
            ),
          ),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 520 ? 2 : 1);
            final w = (c.maxWidth - Insets.lg * (cols - 1)) / cols;
            return Wrap(
              spacing: Insets.lg,
              runSpacing: Insets.lg,
              children: [
                for (final t in tiers)
                  SizedBox(
                    width: w,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(Radii.lg),
                        onTap: () => _editTier(context, ref, t),
                        child: Ink(
                          padding: const EdgeInsets.all(Insets.xl),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(Radii.lg),
                            gradient: LinearGradient(
                              colors: [
                                t.color,
                                Color.lerp(t.color, Colors.black, 0.3)!,
                              ],
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.workspace_premium_rounded,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: Insets.sm),
                                  Expanded(
                                    child: Text(
                                      t.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.titleLarge?.copyWith(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.edit_outlined,
                                    color: Colors.white70,
                                    size: 18,
                                  ),
                                ],
                              ),
                              const SizedBox(height: Insets.lg),
                              Text(
                                t.percent == 0
                                    ? 'Без скидки'
                                    : 'Скидка ${t.percent.toStringAsFixed(0)}%',
                                style: text.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                t.threshold == 0
                                    ? 'С первой покупки'
                                    : 'От ${money.format(t.threshold)} покупок',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: Insets.lg),
                              Text(
                                '${t.customers} клиентов',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (tiers.isNotEmpty) ...[
          const SizedBox(height: Insets.xl),
          AdminCard(
            title: 'Уровни и пороги',
            subtitle: 'С какой суммы покупок клиент получает уровень и какая у него скидка',
            padding: const EdgeInsets.fromLTRB(
              Insets.xl,
              Insets.xl,
              Insets.xl,
              Insets.md,
            ),
            child: Column(
              children: [
                for (final (i, t) in tiers.indexed) ...[
                  if (i > 0) const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        CircleAvatar(radius: 8, backgroundColor: t.color),
                        const SizedBox(width: Insets.md),
                        Expanded(
                          flex: 3,
                          child: Text(
                            t.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            t.threshold == 0
                                ? 'с первой покупки'
                                : 'от ${money.format(t.threshold)}',
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            t.percent == 0
                                ? 'без скидки'
                                : 'скидка ${t.percent.toStringAsFixed(t.percent == t.percent.roundToDouble() ? 0 : 1)}%',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _editTier(context, ref, t),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Изменить'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  static Future<void> _addTier(BuildContext context, WidgetRef ref) =>
      _editTier(context, ref, null);

  static Future<void> _editTier(
    BuildContext context,
    WidgetRef ref,
    TierConfig? tier,
  ) async {
    final result = await showDialog<_TierResult>(
      context: context,
      builder: (_) => _TierDialog(tier: tier, taken: ref.read(tiersProvider)),
    );
    final n = ref.read(tiersProvider.notifier);
    switch (result) {
      case _TierSave(:final value) when tier == null:
        await n.create(value);
      case _TierSave(:final value):
        await n.save(value);
      case _TierDelete() when tier != null:
        await n.delete(tier);
      case _:
    }
  }
}

sealed class _TierResult {}

class _TierSave extends _TierResult {
  _TierSave(this.value);
  final TierConfig value;
}

class _TierDelete extends _TierResult {}

class _TierDialog extends StatefulWidget {
  const _TierDialog({required this.tier, required this.taken});
  final TierConfig? tier;
  final List<TierConfig> taken; // другие уровни — для проверки уникальности

  @override
  State<_TierDialog> createState() => _TierDialogState();
}

class _TierDialogState extends State<_TierDialog> {
  static const _colors = [
    Color(0xFFB45309),
    Color(0xFF64748B),
    Color(0xFFCA8A04),
    AppColors.brand,
    AppColors.fresh,
    AppColors.wholesale,
    Color(0xFF7C3AED),
    Color(0xFF0F172A),
  ];
  final _form = GlobalKey<FormState>();
  late final t = widget.tier;
  late final _name = TextEditingController(text: t?.name);
  late final _threshold = TextEditingController(
    text: t == null ? '' : t!.threshold.toStringAsFixed(0),
  );
  late final _percent = TextEditingController(
    text: t == null ? '' : _fmt(t!.percent),
  );
  late Color _color = t?.color ?? _colors.first;

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  static double? _num(String s) =>
      double.tryParse(s.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.'));

  bool _same(TierConfig o) => widget.tier != null && o.id == widget.tier!.id;

  @override
  void dispose() {
    _name.dispose();
    _threshold.dispose();
    _percent.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      _TierSave(
        TierConfig(
          _name.text.trim(),
          _num(_threshold.text)!,
          _num(_percent.text)!,
          _color,
          t?.customers ?? 0,
          id: t?.id,
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Удалить уровень «${t!.name}»?'),
        content: Text(
          t!.customers == 0
              ? 'Клиентов на этом уровне нет.'
              : '${t!.customers} клиентов потеряют скидку этого уровня — статус пересчитается при следующем заказе.',
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
    if (sure == true && mounted) Navigator.pop(context, _TierDelete());
  }

  @override
  Widget build(BuildContext context) {
    final others = [
      for (final o in widget.taken)
        if (!_same(o)) o,
    ];
    return AlertDialog(
      title: Text(t == null ? 'Новый уровень' : 'Уровень «${t!.name}»'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: t == null,
                decoration: const InputDecoration(
                  labelText: 'Название',
                  hintText: 'Gold',
                ),
                validator: (v) {
                  final name = (v ?? '').trim();
                  if (name.isEmpty) return 'Укажите название';
                  if (name.length > 50) return 'Не длиннее 50 символов';
                  if (others.any(
                    (o) => o.name.toLowerCase() == name.toLowerCase(),
                  )) {
                    return 'Такой уровень уже есть';
                  }
                  return null;
                },
              ),
              const SizedBox(height: Insets.md),
              TextFormField(
                controller: _threshold,
                onTap: () => _selectAll(_threshold),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Сумма покупок от',
                  suffixText: '₽',
                ),
                validator: (v) {
                  final x = _num(v ?? '');
                  if (x == null || x < 0) {
                    return 'Введите сумму, например 10000';
                  }
                  if (x > 10000000) return 'Не больше 10 000 000 ₽';
                  if (others.any((o) => o.threshold == x)) {
                    return 'Такой порог уже у другого уровня';
                  }
                  return null;
                },
              ),
              const SizedBox(height: Insets.md),
              TextFormField(
                controller: _percent,
                onTap: () => _selectAll(_percent),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Скидка',
                  suffixText: '%',
                ),
                validator: (v) {
                  final x = _num(v ?? '');
                  if (x == null || x < 0 || x > 50) return 'От 0 до 50%';
                  return null;
                },
              ),
              const SizedBox(height: Insets.lg),
              Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: [
                  for (final col in _colors)
                    Semantics(
                      button: true,
                      selected: col == _color,
                      label: 'Цвет',
                      child: GestureDetector(
                        onTap: () => setState(() => _color = col),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: col,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: col == _color
                                  ? context.palette.textPrimary
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: col == _color
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 18,
                                )
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (t != null)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: AppColors.lowStock),
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Удалить'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(t == null ? 'Создать' : 'Сохранить'),
        ),
      ],
    );
  }
}

class StaffPage extends ConsumerWidget {
  const StaffPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(adminAuthProvider);
    final staff = ref.watch(staffProvider);
    const colors = {
      'owner': AppColors.brand,
      'manager': AppColors.wholesale,
      'picker': AppColors.hit,
      'courier': AppColors.fresh,
    };
    return ListView(
      padding: const EdgeInsets.all(Insets.xl),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => _invite(context, ref),
            icon: const Icon(Icons.person_add_alt_rounded),
            label: const Text('Добавить сотрудника'),
          ),
        ),
        const SizedBox(height: Insets.lg),
        AdminCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, a) in staff.indexed) ...[
                if (i > 0) const Divider(),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Insets.xl,
                    vertical: Insets.sm,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: (colors[a.role] ?? AppColors.brand)
                        .withValues(alpha: 0.12),
                    child: Text(
                      a.name
                          .split(' ')
                          .where((p) => p.isNotEmpty)
                          .map((p) => p[0])
                          .take(2)
                          .join(),
                      style: TextStyle(
                        color: colors[a.role],
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(
                    a.name + (a.email == me?.email ? '  (вы)' : ''),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    a.isActive ? a.email : '${a.email} · отключён',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: (colors[a.role] ?? AppColors.brand).withValues(
                            alpha: 0.1,
                          ),
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: Text(
                          roleTitles[a.role] ?? a.role,
                          style: TextStyle(
                            color: colors[a.role],
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: Insets.sm),
                      if (a.email == me?.email)
                        const SizedBox(width: 40)
                      else
                        IconButton(
                          tooltip: 'Удалить сотрудника',
                          color: AppColors.lowStock,
                          onPressed: () => _delete(context, ref, a),
                          icon: const Icon(Icons.person_remove_outlined),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    StaffMember m,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(
          Icons.person_remove_outlined,
          color: AppColors.lowStock,
          size: 36,
        ),
        title: Text('Удалить ${m.name}?'),
        content: Text(
          '${roleTitles[m.role] ?? m.role} сразу потеряет доступ к админке — '
          'даже если сейчас в ней работает. Заказы, которые он собирал или вёз, останутся.',
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
    if (ok != true || !context.mounted) return;
    final deleted = await ref.read(staffProvider.notifier).delete(m);
    if (deleted == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted
              ? '${m.name} удалён(а) из сотрудников'
              : '${m.name}: доступ в админку снят. Аккаунт покупателя сохранён — у него есть свои заказы',
        ),
      ),
    );
  }

  static Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final email = TextEditingController(),
        name = TextEditingController(),
        password = TextEditingController();
    var role = 'picker';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('Новый сотрудник'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Имя и фамилия'),
                ),
                const SizedBox(height: Insets.md),
                TextField(
                  controller: email,
                  decoration: const InputDecoration(labelText: 'Рабочий email'),
                ),
                const SizedBox(height: Insets.md),
                TextField(
                  controller: password,
                  decoration: const InputDecoration(
                    labelText: 'Временный пароль',
                    helperText:
                        'Минимум 10 символов, буквы и цифры — передайте лично',
                  ),
                ),
                const SizedBox(height: Insets.md),
                Wrap(
                  spacing: Insets.sm,
                  runSpacing: Insets.sm,
                  children: [
                    for (final (v, l) in const [
                      ('picker', 'Сборщик'),
                      ('courier', 'Курьер'),
                      ('manager', 'Менеджер'),
                      ('owner', 'Владелец'),
                    ])
                      ChoiceChip(
                        label: Text(l),
                        selected: role == v,
                        onSelected: (_) => setState(() => role = v),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    if (password.text.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пароль должен быть не короче 10 символов'),
        ),
      );
      return;
    }
    final created = await ref
        .read(staffProvider.notifier)
        .create(
          email: email.text.trim(),
          name: name.text.trim(),
          role: role,
          password: password.text,
        );
    if (created && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Сотрудник добавлен')));
    }
  }
}

/// Тап по числовому полю выделяет значение целиком — новое число заменяет старое, а не дописывается.
void _selectAll(TextEditingController c) =>
    c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.url,
    required this.busy,
    required this.onPick,
    this.onRemove,
    this.error,
  });
  final String? url;
  final bool busy;
  final String? error;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: palette.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: busy
              ? const Center(child: CircularProgressIndicator())
              : url == null
              ? Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 36,
                  color: palette.textSecondary,
                )
              : Padding(
                  padding: const EdgeInsets.all(6),
                  child: AppImage(imageUrl: url!, fit: BoxFit.contain),
                ),
        ),
        const SizedBox(width: Insets.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.xs,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : onPick,
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: Text(
                      url == null ? 'Загрузить с компьютера' : 'Заменить фото',
                    ),
                  ),
                  if (onRemove != null)
                    TextButton(
                      onPressed: onRemove,
                      child: const Text('Убрать'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'JPG, PNG или WebP до 10 МБ. Лучше квадрат 1000×1000 px '
                '(минимум 300×300), товар по центру, белый или прозрачный фон. '
                'Большие фото уменьшим автоматически.',
                style: TextStyle(color: palette.textSecondary, fontSize: 12),
              ),
              if (error != null) ...[
                const SizedBox(height: 4),
                Text(
                  error!,
                  style: const TextStyle(
                    color: AppColors.lowStock,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
