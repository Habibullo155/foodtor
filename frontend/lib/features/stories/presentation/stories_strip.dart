import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_image.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/story.dart';
import 'story_viewer.dart';

class StoriesStrip extends ConsumerWidget {
  const StoriesStrip({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: Insets.lg),
  });
  final EdgeInsets padding;

  static const double avatarSize = 68;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stories = ref.watch(storiesProvider);
    if (stories.isEmpty) return const SizedBox.shrink();
    final seen = ref.watch(seenStoriesProvider);
    // Непросмотренные — первыми: свежий контент всегда в зоне видимости
    final ordered = [
      ...stories.where((s) => !seen.contains(s.id)),
      ...stories.where((s) => seen.contains(s.id)),
    ];

    return SizedBox(
      height: avatarSize + 34,
      child: ListView.separated(
        padding: padding,
        scrollDirection: Axis.horizontal,
        itemCount: ordered.length,
        separatorBuilder: (_, _) => const SizedBox(width: Insets.md),
        itemBuilder: (context, i) => _StoryAvatar(
          story: ordered[i],
          seen: seen.contains(ordered[i].id),
          onTap: () => StoryViewer.show(context, ordered, i),
        ),
      ),
    );
  }
}

class _StoryAvatar extends StatefulWidget {
  const _StoryAvatar({
    required this.story,
    required this.seen,
    required this.onTap,
  });
  final Story story;
  final bool seen;
  final VoidCallback onTap;

  @override
  State<_StoryAvatar> createState() => _StoryAvatarState();
}

class _StoryAvatarState extends State<_StoryAvatar> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const size = StoriesStrip.avatarSize;
    return Semantics(
      button: true,
      label: 'История: ${widget.story.title}',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedScale(
            scale: _pressed ? 0.92 : 1,
            duration: const Duration(milliseconds: 120),
            child: SizedBox(
              width: size + 6,
              child: Column(
                children: [
                  Container(
                    width: size,
                    height: size,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: widget.seen
                          ? null
                          : const SweepGradient(
                              colors: [
                                ...AppColors.storyRing,
                                Color(0xFFF59E0B),
                              ],
                            ),
                      color: widget.seen ? context.palette.border : null,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.palette.surface,
                      ),
                      child: ClipOval(
                        child: ColoredBox(
                          color: widget.story.color.withValues(alpha: 0.14),
                          child: Padding(
                            padding: const EdgeInsets.all(9),
                            child: AppImage(
                              imageUrl: widget.story.coverUrl,
                              fit: BoxFit.contain,
                              memCacheWidth: 200,
                              errorWidget: (_, _, _) => const SizedBox(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.story.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: widget.seen
                          ? FontWeight.w500
                          : FontWeight.w600,
                      color: widget.seen
                          ? context.palette.textSecondary
                          : context.palette.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
