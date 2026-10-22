import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_image.dart';

import '../../../core/theme/app_theme.dart';
import '../../catalog/presentation/providers/catalog_filter.dart';
import '../domain/story.dart';

class StoryViewer extends ConsumerStatefulWidget {
  const StoryViewer({
    super.key,
    required this.stories,
    required this.initialIndex,
  });

  final List<Story> stories;
  final int initialIndex;

  static Future<void> show(
    BuildContext context,
    List<Story> stories,
    int index,
  ) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) =>
            StoryViewer(stories: stories, initialIndex: index),
        transitionsBuilder: (_, anim, _, child) {
          final curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween(begin: 0.92, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  ConsumerState<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends ConsumerState<StoryViewer>
    with SingleTickerProviderStateMixin {
  static const _slideDuration = Duration(seconds: 5);

  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late final AnimationController _progress =
      AnimationController(vsync: this, duration: _slideDuration)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _next();
        });
  late int _story = widget.initialIndex;
  int _slide = 0;
  double _dragDy = 0;

  Story get _current => widget.stories[_story];

  @override
  void initState() {
    super.initState();
    _onStoryShown();
  }

  @override
  void dispose() {
    _progress.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _onStoryShown() {
    // Отметку «просмотрено» ставим после кадра (нельзя менять провайдер во время build).
    // Notifier и id захватываем сейчас: к моменту колбэка экран может уже закрываться,
    // и ref деактивированного элемента использовать нельзя.
    final seen = ref.read(seenStoriesProvider.notifier);
    final id = _current.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      seen.markSeen(id);
      // precacheImage читает MediaQuery — в initState это запрещено, поэтому тоже после кадра
      if (mounted) _precacheNext();
    });
    _progress.forward(from: 0);
  }

  void _precacheNext() {
    final next = _slide + 1 < _current.slides.length
        ? _current.slides[_slide + 1]
        : (_story + 1 < widget.stories.length
              ? widget.stories[_story + 1].slides.first
              : null);
    if (next != null) precacheImage(AppImage.provider(next.imageUrl), context);
  }

  void _next() {
    if (_slide + 1 < _current.slides.length) {
      setState(() => _slide++);
      _progress.forward(from: 0);
      _precacheNext();
    } else if (_story + 1 < widget.stories.length) {
      _pages.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _prev() {
    if (_slide > 0) {
      setState(() => _slide--);
      _progress.forward(from: 0);
    } else if (_story > 0) {
      _pages.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      _progress.forward(from: 0);
    }
  }

  void _onCta(StorySlide slide) {
    if (slide.ctaCategoryId case final id?) {
      ref
          .read(catalogFilterProvider.notifier)
          .update((f) => f.copyWith(categoryId: () => id));
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _prev,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, c) {
            final framed = c.maxWidth >= 600;
            final viewer = PageView.builder(
              controller: _pages,
              itemCount: widget.stories.length,
              onPageChanged: (i) {
                setState(() {
                  _story = i;
                  _slide = 0;
                });
                _onStoryShown();
              },
              itemBuilder: (_, i) => i == _story
                  ? _StoryPage(
                      story: _current,
                      slideIndex: _slide,
                      progress: _progress,
                      onTapLeft: _prev,
                      onTapRight: _next,
                      onPause: _progress.stop,
                      onResume: _progress.forward,
                      onCta: _onCta,
                    )
                  : const ColoredBox(color: Colors.black),
            );

            final body = GestureDetector(
              // Свайп вниз — закрыть (как в Instagram)
              onVerticalDragUpdate: (d) => setState(
                () => _dragDy = (_dragDy + d.delta.dy).clamp(0, 400),
              ),
              onVerticalDragEnd: (d) {
                if (_dragDy > 120 || d.velocity.pixelsPerSecond.dy > 800) {
                  Navigator.of(context).maybePop();
                } else {
                  setState(() => _dragDy = 0);
                }
              },
              child: AnimatedContainer(
                duration: _dragDy == 0
                    ? const Duration(milliseconds: 200)
                    : Duration.zero,
                transform: Matrix4.translationValues(0, _dragDy, 0),
                child: viewer,
              ),
            );

            if (!framed) return Material(color: Colors.black, child: body);

            return Material(
              color: Colors.black.withValues(alpha: 0.92),
              child: Stack(
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: c.maxHeight * 0.92,
                      ),
                      child: AspectRatio(
                        aspectRatio: 9 / 16,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.lg),
                          child: body,
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: const Alignment(-0.55, 0),
                    child: _NavArrow(
                      icon: Icons.chevron_left_rounded,
                      onTap: _prev,
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0.55, 0),
                    child: _NavArrow(
                      icon: Icons.chevron_right_rounded,
                      onTap: _next,
                    ),
                  ),
                  Positioned(
                    top: 24,
                    right: 24,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StoryPage extends StatelessWidget {
  const _StoryPage({
    required this.story,
    required this.slideIndex,
    required this.progress,
    required this.onTapLeft,
    required this.onTapRight,
    required this.onPause,
    required this.onResume,
    required this.onCta,
  });

  final Story story;
  final int slideIndex;
  final Animation<double> progress;
  final VoidCallback onTapLeft;
  final VoidCallback onTapRight;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final ValueChanged<StorySlide> onCta;

  @override
  Widget build(BuildContext context) {
    final slide = story.slides[slideIndex];
    final text = Theme.of(context).textTheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                story.color,
                Color.lerp(story.color, Colors.black, 0.45)!,
              ],
            ),
          ),
        ),
        // Продукт крупно, чуть выше центра — место снизу под заголовок и CTA
        Align(
          alignment: const Alignment(0, -0.25),
          child: FractionallySizedBox(
            widthFactor: 0.72,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(
                  scale: Tween(begin: 0.9, end: 1.0).animate(a),
                  child: c,
                ),
              ),
              child: AppImage(
                key: ValueKey(slide.imageUrl),
                imageUrl: slide.imageUrl,
                fit: BoxFit.contain,
                placeholder: (_, _) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (_, _, _) => const SizedBox(),
              ),
            ),
          ),
        ),
        // Затемнение сверху и снизу — текст читается на любой картинке
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x99000000),
                Color(0x00000000),
                Color(0x00000000),
                Color(0xCC000000),
              ],
              stops: [0, 0.22, 0.55, 1],
            ),
          ),
        ),
        // Зоны тапа: левая треть — назад, остальное — вперёд; удержание — пауза
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: onTapLeft,
                onLongPressStart: (_) => onPause(),
                onLongPressEnd: (_) => onResume(),
              ),
            ),
            Expanded(
              flex: 2,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: onTapRight,
                onLongPressStart: (_) => onPause(),
                onLongPressEnd: (_) => onResume(),
              ),
            ),
          ],
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.md,
              Insets.sm,
              Insets.md,
              Insets.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProgressBars(
                  count: story.slides.length,
                  current: slideIndex,
                  progress: progress,
                ),
                const SizedBox(height: Insets.md),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.white24,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: AppImage(
                          imageUrl: story.coverUrl,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    Text(
                      story.title,
                      style: text.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    Text(
                      story.kind.label,
                      style: text.labelSmall?.copyWith(color: Colors.white70),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  slide.headline,
                  style: text.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                if (slide.caption != null) ...[
                  const SizedBox(height: Insets.sm),
                  Text(
                    slide.caption!,
                    style: text.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
                if (slide.ctaLabel != null) ...[
                  const SizedBox(height: Insets.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: context.palette.textPrimary,
                        padding: const EdgeInsets.symmetric(
                          vertical: Insets.lg,
                        ),
                      ),
                      onPressed: () => onCta(slide),
                      child: Text(slide.ctaLabel!),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressBars extends StatelessWidget {
  const _ProgressBars({
    required this.count,
    required this.current,
    required this.progress,
  });
  final int count;
  final int current;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: AnimatedBuilder(
                animation: progress,
                builder: (_, _) => LinearProgressIndicator(
                  value: i < current ? 1 : (i == current ? progress.value : 0),
                  minHeight: 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.35),
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _NavArrow extends StatelessWidget {
  const _NavArrow({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton.filled(
    style: IconButton.styleFrom(
      backgroundColor: Colors.white24,
      foregroundColor: Colors.white,
    ),
    iconSize: 32,
    onPressed: onTap,
    icon: Icon(icon),
  );
}
