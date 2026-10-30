import 'package:flutter/material.dart';
import '../../../app/connectly_theme.dart';
import '../../feed/domain/feed_models.dart';
import '../../feed/presentation/feed_widgets.dart';
import '../data/people_repository.dart';

class PersonCard extends StatelessWidget {
  const PersonCard(
      {required this.entry,
      required this.busy,
      required this.onFollow,
      required this.onFriend,
      super.key});
  final LocatedPerson entry;
  final bool busy;
  final VoidCallback onFollow;
  final ValueChanged<String> onFriend;
  @override
  Widget build(BuildContext context) {
    final p = entry.person;
    final distance = entry.distanceKm;
    return Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: ConnectlyTheme.surface,
            borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            FeedAvatar(p.name),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(p.name,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600)),
                  Text(
                      distance == null
                          ? (entry.location == null
                              ? 'No shared location'
                              : 'Saved map pin')
                          : '${distance < 1 ? '${(distance * 1000).round()} m' : '${distance.toStringAsFixed(1)} km'} from your pin',
                      style: const TextStyle(color: feedMuted, fontSize: 12)),
                ])),
            if (busy)
              const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          const SizedBox(height: 12),
          Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                    onPressed: busy ? null : onFollow,
                    icon:
                        Icon(p.isFollowing ? Icons.check : Icons.add, size: 18),
                    label: Text(p.isFollowing ? 'Following' : 'Follow')),
                ..._friendActions(p),
              ]),
        ]));
  }

  List<Widget> _friendActions(FeedPerson p) => switch (p.friendship) {
        'incoming' => [
            FilledButton(
                onPressed: busy ? null : () => onFriend('accept'),
                child: const Text('Accept request')),
            TextButton(
                onPressed: busy ? null : () => onFriend('remove'),
                child: const Text('Decline'))
          ],
        'outgoing' => [
            TextButton.icon(
                onPressed: busy ? null : () => onFriend('remove'),
                icon: const Icon(Icons.schedule, size: 18),
                label: const Text('Cancel request'))
          ],
        'friends' => [
            PopupMenuButton<String>(
                enabled: !busy,
                tooltip: 'Friend options',
                onSelected: onFriend,
                itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'remove', child: Text('Remove friend'))
                    ],
                child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Friends ✓',
                        style: TextStyle(color: ConnectlyTheme.yellow))))
          ],
        _ => [
            TextButton.icon(
                onPressed: busy ? null : () => onFriend('request'),
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('Add friend'))
          ],
      };
}
