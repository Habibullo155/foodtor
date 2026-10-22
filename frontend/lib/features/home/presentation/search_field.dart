import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../catalog/presentation/providers/catalog_filter.dart';

/// Поиск по каталогу с debounce: фильтр обновляется через 250 мс после последнего символа,
/// а не на каждое нажатие (в проде — меньше запросов к API).
class CatalogSearchField extends ConsumerStatefulWidget {
  const CatalogSearchField({super.key, this.onSubmitted});
  final VoidCallback? onSubmitted;

  @override
  ConsumerState<CatalogSearchField> createState() => _CatalogSearchFieldState();
}

class _CatalogSearchFieldState extends ConsumerState<CatalogSearchField> {
  late final _controller = TextEditingController(
    text: ref.read(catalogFilterProvider).query,
  );
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {}); // показать/скрыть кнопку очистки
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      ref.read(catalogFilterProvider.notifier).setQuery(value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: _onChanged,
      onSubmitted: (_) => widget.onSubmitted?.call(),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Искать овощи, фрукты, крупы…',
        prefixIcon: Icon(
          Icons.search_rounded,
          color: context.palette.textSecondary,
        ),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Очистить',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () {
                  _controller.clear();
                  _onChanged('');
                },
              ),
      ),
    );
  }
}
