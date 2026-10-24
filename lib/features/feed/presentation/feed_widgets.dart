import 'package:flutter/material.dart';
import '../../../app/connectly_theme.dart';

const feedMuted = Color(0xFFB8C5DA);
const reactionLabels = {
  'like': 'Like',
  'love': 'Love',
  'celebrate': 'Celebrate',
  'insightful': 'Insightful'
};
const reactionIcons = {
  'like': Icons.thumb_up_alt_outlined,
  'love': Icons.favorite_outline,
  'celebrate': Icons.celebration_outlined,
  'insightful': Icons.lightbulb_outline
};

class FeedAvatar extends StatelessWidget {
  const FeedAvatar(this.name, {super.key});
  final String name;
  @override
  Widget build(BuildContext context) => CircleAvatar(
        backgroundColor: ConnectlyTheme.yellow.withValues(alpha: .14),
        foregroundColor: ConnectlyTheme.yellow,
        child: Text(
            name.trim().isEmpty
                ? '?'
                : name.trim().characters.first.toUpperCase(),
            style: const TextStyle(
                fontFamily: 'Urbanist', fontWeight: FontWeight.w700)),
      );
}

class FeedNotice extends StatelessWidget {
  const FeedNotice(
      {required this.icon,
      required this.title,
      required this.message,
      this.action,
      super.key});
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: ConnectlyTheme.yellow, size: 44),
          const SizedBox(height: 18),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: 'Urbanist',
                  fontSize: 23,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: feedMuted, height: 1.5)),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      );
}

String postTime(DateTime time) {
  final local = time.toLocal();
  final age = DateTime.now().difference(time);
  if (age.inSeconds < 60) return 'Just now';
  if (age.inMinutes < 60) return '${age.inMinutes}m ago';
  if (age.inHours < 24) return '${age.inHours}h ago';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${months[local.month - 1]} ${local.day}${local.year == DateTime.now().year ? '' : ', ${local.year}'}';
}
