import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_image.dart';
import '../data/admin_repository.dart';

/// Фото с компьютера или по ссылке: превью, «Загрузить», «Убрать».
class PhotoField extends ConsumerStatefulWidget {
  const PhotoField({
    super.key,
    required this.value,
    required this.onChanged,
    this.kind = 'products',
    this.hint = 'JPG, PNG или WebP до 10 МБ, от 300×300 px',
    this.previewWidth = 96,
    this.previewHeight = 96,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final String kind;
  final String hint;
  final double previewWidth;
  final double previewHeight;

  @override
  ConsumerState<PhotoField> createState() => _PhotoFieldState();
}

class _PhotoFieldState extends ConsumerState<PhotoField> {
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    final file = files.singleOrNull;
    if (file == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        throw const FormatException('Файл больше 10 МБ — уменьшите фото');
      }
      final url = await ref
          .read(adminRepositoryProvider)
          .uploadProductImage(file.name, bytes, kind: widget.kind);
      widget.onChanged(url);
    } catch (e) {
      setState(() => _error = e is FormatException ? e.message : e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final v = widget.value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: widget.previewWidth,
          height: widget.previewHeight,
          decoration: BoxDecoration(
            color: palette.surfaceMuted,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          clipBehavior: Clip.antiAlias,
          child: v == null
              ? Icon(Icons.image_outlined, color: palette.textSecondary)
              : AppImage(imageUrl: v, fit: BoxFit.cover),
        ),
        const SizedBox(width: Insets.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _pick,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_rounded, size: 18),
                    label: Text(v == null ? 'Загрузить фото' : 'Заменить'),
                  ),
                  if (v != null)
                    TextButton(
                      onPressed: () => widget.onChanged(null),
                      child: const Text('Убрать'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _error ?? widget.hint,
                style: TextStyle(
                  fontSize: 12,
                  color: _error == null
                      ? palette.textSecondary
                      : AppColors.lowStock,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
