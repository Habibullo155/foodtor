import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../network/api_client.dart' show apiBaseUrl;

/// Единая точка показа изображений товаров/историй/категорий.
/// `assets/...` — из бандла приложения (демо-данные, офлайн), иначе — сеть с дисковым кэшем (CDN в проде).
/// Сигнатура повторяет CachedNetworkImage, чтобы переключение источника не трогало UI-код.
class AppImage extends StatelessWidget {
  const AppImage({
    super.key,
    required this.imageUrl,
    this.fit,
    this.memCacheWidth,
    this.fadeInDuration = const Duration(milliseconds: 200),
    this.placeholder,
    this.errorWidget,
  });

  final String imageUrl;
  final BoxFit? fit;
  final int? memCacheWidth;
  final Duration fadeInDuration;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, Object)? errorWidget;

  static bool _isAsset(String url) => url.startsWith('assets/');

  /// «/media/products/…» (загружено в админке) → полный адрес API.
  static String resolve(String url) =>
      url.startsWith('/') ? '${apiBaseUrl()}$url' : url;

  static ImageProvider provider(String url) => _isAsset(url)
      ? AssetImage(url)
      : url.startsWith('data:')
      ? MemoryImage(UriData.parse(url).contentAsBytes())
      : CachedNetworkImageProvider(resolve(url));

  @override
  Widget build(BuildContext context) {
    if (imageUrl.startsWith('data:')) {
      // демо: фото, выбранное с компьютера, живёт в памяти вкладки
      return Image.memory(
        base64Decode(imageUrl.substring(imageUrl.indexOf(',') + 1)),
        fit: fit,
        cacheWidth: memCacheWidth,
      );
    }
    if (!_isAsset(imageUrl)) {
      return CachedNetworkImage(
        imageUrl: resolve(imageUrl),
        fit: fit,
        memCacheWidth: memCacheWidth,
        fadeInDuration: fadeInDuration,
        placeholder: placeholder,
        errorWidget: errorWidget,
      );
    }
    return Image.asset(
      imageUrl,
      fit: fit,
      cacheWidth: memCacheWidth,
      errorBuilder: errorWidget == null
          ? null
          : (c, e, _) => errorWidget!(c, imageUrl, e),
      frameBuilder: (context, child, frame, sync) => sync
          ? child
          : AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: fadeInDuration,
              child: child,
            ),
    );
  }
}
