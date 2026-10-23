import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../data/admin_data.dart';
import '../data/admin_repository.dart';
import '../widgets/admin_widgets.dart';

class SupportPage extends ConsumerStatefulWidget {
  const SupportPage({super.key});

  @override
  ConsumerState<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends ConsumerState<SupportPage> {
  int? _open;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // новые обращения подтягиваем сами — менеджеру не нужно обновлять страницу
    _poll = Timer.periodic(
      const Duration(seconds: 20),
      (_) => ref.read(supportThreadsProvider.notifier).reload(),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final threads = ref.watch(supportThreadsProvider);
    final current = threads.where((t) => t.userId == _open).firstOrNull;
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final list = _Inbox(
          threads: threads,
          selected: _open,
          onOpen: (t) {
            setState(() => _open = t.userId);
            ref.read(supportThreadsProvider.notifier).markRead(t.userId);
          },
        );
        if (!wide) {
          return current == null
              ? list
              : _Chat(
                  thread: current,
                  onBack: () => setState(() => _open = null),
                );
        }
        return Padding(
          padding: const EdgeInsets.all(Insets.xl),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 360, child: list),
              const SizedBox(width: Insets.lg),
              Expanded(
                child: current == null
                    ? const AdminCard(
                        child: EmptyState(
                          icon: Icons.forum_outlined,
                          title: 'Выберите обращение',
                          subtitle: 'Покупатели пишут со страницы «Поддержка» на сайте',
                        ),
                      )
                    : _Chat(thread: current),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Inbox extends StatelessWidget {
  const _Inbox({
    required this.threads,
    required this.selected,
    required this.onOpen,
  });
  final List<SupportThread> threads;
  final int? selected;
  final ValueChanged<SupportThread> onOpen;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: context.palette.textSecondary, fontSize: 13);
    return AdminCard(
      padding: EdgeInsets.zero,
      child: threads.isEmpty
          ? const EmptyState(
              icon: Icons.mark_chat_read_outlined,
              title: 'Обращений нет',
              subtitle: 'Когда покупатель напишет в поддержку, сообщение появится здесь',
            )
          : ListView.separated(
              shrinkWrap: true,
              itemCount: threads.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final t = threads[i];
                return ListTile(
                  selected: t.userId == selected,
                  selectedTileColor: AppColors.brand.withValues(alpha: 0.08),
                  onTap: () => onOpen(t),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.brand.withValues(alpha: 0.12),
                    child: Text(
                      t.name.isEmpty ? '?' : t.name[0],
                      style: const TextStyle(
                        color: AppColors.brand,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(
                    t.name,
                    style: TextStyle(
                      fontWeight: t.unread > 0
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${t.lastFromStaff ? 'Вы: ' : ''}${t.lastText}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        timeAgo(t.lastAt),
                        style: muted.copyWith(fontSize: 11),
                      ),
                      if (t.unread > 0) ...[
                        const SizedBox(height: 4),
                        Badge.count(
                          count: t.unread,
                          backgroundColor: AppColors.lowStock,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _Chat extends ConsumerStatefulWidget {
  const _Chat({required this.thread, this.onBack});
  final SupportThread thread;
  final VoidCallback? onBack;

  @override
  ConsumerState<_Chat> createState() => _ChatState();
}

class _ChatState extends ConsumerState<_Chat> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  List<SupportMessage>? _messages;
  bool _sending = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void didUpdateWidget(_Chat old) {
    super.didUpdateWidget(old);
    if (old.thread.userId != widget.thread.userId) {
      setState(() => _messages = null);
      _load();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await ref
          .read(adminRepositoryProvider)
          .supportThread(widget.thread.userId);
      if (mounted) setState(() => _messages = m);
    } catch (e) {
      ref.read(adminErrorProvider.notifier).report(e);
    }
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final m = await ref
          .read(adminRepositoryProvider)
          .answerSupport(widget.thread.userId, text);
      _text.clear();
      if (mounted) setState(() => _messages = m);
      ref.read(supportThreadsProvider.notifier).reload();
    } catch (e) {
      ref.read(adminErrorProvider.notifier).report(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.thread;
    final palette = context.palette;
    final messages = _messages;
    return AdminCard(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: widget.onBack == null
                ? null
                : IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
            title: Text(
              t.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text([t.phone, t.email].whereType<String>().join(' · ')),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 420,
            child: messages == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.all(Insets.lg),
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final m = messages[messages.length - 1 - i];
                      return Align(
                        alignment: m.fromStaff
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 460),
                          margin: const EdgeInsets.only(bottom: Insets.sm),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: m.fromStaff
                                ? AppColors.brand
                                : palette.surfaceMuted,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (m.fromStaff)
                                Text(
                                  m.author,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              Text(
                                m.text,
                                style: TextStyle(
                                  color: m.fromStaff
                                      ? Colors.white
                                      : palette.textPrimary,
                                ),
                              ),
                              Text(
                                DateFormat(
                                  'd MMM, HH:mm',
                                  'ru',
                                ).format(m.createdAt),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: m.fromStaff
                                      ? Colors.white70
                                      : palette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(Insets.md),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      hintText: 'Ответ покупателю',
                      counterText: '',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: Insets.sm),
                FilledButton(
                  onPressed: _sending ? null : _send,
                  child: const Text('Ответить'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
