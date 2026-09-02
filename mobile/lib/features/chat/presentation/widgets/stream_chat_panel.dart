import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme.dart';
import '../../../auth/domain/auth_state.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/chat_message.dart';
import '../providers/chat_provider.dart';

/// Le chat d'un live : un salon par flux, réservé à ceux qui sont dans le
/// live. Se connecte à l'affichage, se déconnecte quand le widget disparaît.
class StreamChatPanel extends ConsumerStatefulWidget {
  final String streamId;

  const StreamChatPanel({super.key, required this.streamId});

  @override
  ConsumerState<StreamChatPanel> createState() => _StreamChatPanelState();
}

class _StreamChatPanelState extends ConsumerState<StreamChatPanel> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    ref.read(chatProvider(widget.streamId).notifier).send(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider(widget.streamId));
    final auth = ref.watch(authProvider);
    final myUserId = auth is AuthAuthenticated ? auth.user.id : null;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline,
                    size: 18, color: context.colors.accent),
                const SizedBox(width: 8),
                Text(
                  'Chat du live',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: context.colors.text1,
                      ),
                ),
                const Spacer(),
                if (chat.statusText.isNotEmpty)
                  Text(
                    chat.statusText,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: context.colors.textMuted),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: context.colors.divider),
          Expanded(
            child: chat.messages.isEmpty
                ? Center(
                    child: Text(
                      chat.isConnected
                          ? 'Soyez le premier à écrire !'
                          : chat.statusText,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: context.colors.textMuted),
                    ),
                  )
                // reverse + index inversé : la liste colle au dernier
                // message, comme un chat, sans gérer de ScrollController.
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: chat.messages.length,
                    itemBuilder: (context, index) {
                      final message =
                          chat.messages[chat.messages.length - 1 - index];
                      if (message.isPresence) {
                        return _PresenceLine(message: message);
                      }
                      return _MessageBubble(
                        message: message,
                        isMine: message.userId == myUserId,
                      );
                    },
                  ),
          ),
          Divider(height: 1, color: context.colors.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: chat.isConnected,
                    maxLength: 500,
                    style: TextStyle(color: context.colors.text1),
                    decoration: InputDecoration(
                      hintText: chat.isConnected
                          ? 'Écrire un message…'
                          : 'Chat indisponible',
                      hintStyle: TextStyle(color: context.colors.textMuted),
                      counterText: '',
                      isDense: true,
                      border: InputBorder.none,
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  color: context.colors.accent,
                  tooltip: 'Envoyer le message',
                  onPressed: chat.isConnected ? _send : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ligne système : « untel a rejoint / quitté le chat ».
class _PresenceLine extends StatelessWidget {
  final ChatMessage message;

  const _PresenceLine({required this.message});

  @override
  Widget build(BuildContext context) {
    final joined = message.type == ChatMessage.typeUserJoined;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Text(
          joined
              ? '${message.username} a rejoint le chat'
              : '${message.username} a quitté le chat',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.colors.textMuted,
                fontStyle: FontStyle.italic,
              ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;

  const _MessageBubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final time = DateFormat.Hm().format(message.sentAt.toLocal());
    return Semantics(
      label: '${message.username}, $time : ${message.text}',
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: isMine
                ? context.colors.accent.withValues(alpha: 0.18)
                : context.colors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isMine ? 'Vous' : message.username,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isMine
                              ? context.colors.accent
                              : context.colors.text2,
                        ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    time,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: context.colors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                message.text,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: context.colors.text1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
