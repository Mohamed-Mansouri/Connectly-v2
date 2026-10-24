import 'package:flutter/material.dart';
import '../../../app/connectly_theme.dart';

const chatMuted = Color(0xFFB8C5DA);

class ChatAvatar extends StatelessWidget {
  const ChatAvatar(this.name, {this.group = false, super.key});
  final String name;
  final bool group;
  @override
  Widget build(BuildContext context) => CircleAvatar(
      backgroundColor: ConnectlyTheme.yellow.withValues(alpha: .14),
      foregroundColor: ConnectlyTheme.yellow,
      child: group
          ? const Icon(Icons.group_outlined)
          : Text(
              name.trim().isEmpty
                  ? '?'
                  : name.trim().characters.first.toUpperCase(),
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontFamily: 'Urbanist')));
}

class ChatNotice extends StatelessWidget {
  const ChatNotice(
      {required this.title, required this.message, this.action, super.key});
  final String title;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.forum_outlined,
            color: ConnectlyTheme.yellow, size: 44),
        const SizedBox(height: 18),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontFamily: 'Urbanist',
                fontSize: 24,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: chatMuted, height: 1.5)),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ]));
}

String messageTime(DateTime value) {
  final time = value.toLocal();
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

String messageDate(DateTime value) {
  final date = value.toLocal();
  final today = DateTime.now();
  final delta = DateTime(today.year, today.month, today.day)
      .difference(DateTime(date.year, date.month, date.day))
      .inDays;
  if (delta == 0) return 'Today';
  if (delta == 1) return 'Yesterday';
  return '${date.day}/${date.month}/${date.year}';
}
