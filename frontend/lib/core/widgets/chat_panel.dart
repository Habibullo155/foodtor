import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/account/data/account_api.dart' show OrderMessage;
import '../../features/account/presentation/order_details.dart' show ChatBubble;
import '../theme/app_theme.dart';

/// Чат внутри приложения (покупатель ↔ курьер): лента + поле ввода + быстрые ответы.
/// Пока открыт — подтягивает новые сообщения раз в 8 секунд.
class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.load,
    required this.send,
    required this.mineIsStaff,
    this.hint = 'Сообщение…',
    this.closed = false,
    this.quickReplies = const [],
    this.emptyText = 'Сообщений пока нет',
  });

  final Future<List<OrderMessage>> Function() load;
  final Future<List<OrderMessage>> Function(String text) send;
  final bool mineIsStaff;
  final String hint;
  final bool closed;
  final List<String> quickReplies;
  final String emptyText;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _text = TextEditingController();
  List<OrderMessage>? _messages;
  String? _error;
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    if (!widget.closed) {
      _poll = Timer.periodic(const Duration(seconds: 8), (_) => _refresh());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final m = await widget.load();
      if (mounted) {
        setState(() {
          _messages = m;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _send([String? preset]) async {
    final msg = (preset ?? _text.text).trim();
    if (msg.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final m = await widget.send(msg);
      _text.clear();
      if (mounted) {
        setState(() {
          _messages = m;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = _messages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (messages == null && _error == null)
          const Padding(
            padding: EdgeInsets.all(Insets.lg),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (messages != null && messages.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Insets.md),
            child: Text(
              widget.emptyText,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.textSecondary),
            ),
          )
        else if (messages != null)
          for (final m in messages)
            ChatBubble(message: m, mineIsStaff: widget.mineIsStaff),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: AppColors.lowStock)),
        if (!widget.closed) ...[
          if (widget.quickReplies.isNotEmpty) ...[
            const SizedBox(height: Insets.sm),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: [
                for (final q in widget.quickReplies)
                  ActionChip(label: Text(q), onPressed: () => _send(q)),
              ],
            ),
          ],
          const SizedBox(height: Insets.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 1000,
                  buildCounter: (
                    _, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => null,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: Insets.sm),
              IconButton.filled(
                tooltip: 'Отправить',
                onPressed: _busy ? null : _send,
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
