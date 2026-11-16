/// Pure text rules for #hashtags, @mentions and search queries.
///
/// A tag is `#` followed by 1–40 letters, digits or underscores and is stored
/// in lower case. A mention is `@` followed by an account handle (the part of
/// the email before `@`, e.g. `amal` for amal@g.m). Neither may be glued to a
/// preceding word, so `mail@g.m` inside a sentence is not a mention.
library;

final tagPattern =
    RegExp(r'(?<![\p{L}\p{N}_#])#([\p{L}\p{N}_]{1,40})', unicode: true);
final mentionPattern =
    RegExp(r'(?<![\p{L}\p{N}_@.])@([A-Za-z0-9_.\-]{1,40})', unicode: true);
final _wordPattern = RegExp(r'[\p{L}\p{N}_]+', unicode: true);

String _cleanHandle(String raw) =>
    raw.replaceAll(RegExp(r'[.\-]+$'), '').toLowerCase();

/// Distinct lower-case tags in [body], in order of appearance (max 20).
List<String> extractTags(String body) => {
      for (final m in tagPattern.allMatches(body)) m.group(1)!.toLowerCase()
    }.take(20).toList();

/// Distinct lower-case handles mentioned in [body] (max 20).
List<String> extractMentions(String body) => {
      for (final m in mentionPattern.allMatches(body))
        if (_cleanHandle(m.group(1)!).isNotEmpty) _cleanHandle(m.group(1)!)
    }.take(20).toList();

/// One piece of a post body, used to draw tappable tags and mentions.
class PostTextPart {
  const PostTextPart(this.text, {this.tag, this.mention});
  final String text;
  final String? tag;
  final String? mention;
}

/// Splits [body] into plain text, tag and mention parts.
List<PostTextPart> splitPostText(String body) {
  final matches = [
    ...tagPattern.allMatches(body).map((m) => (m, true)),
    ...mentionPattern.allMatches(body).map((m) => (m, false)),
  ]..sort((a, b) => a.$1.start.compareTo(b.$1.start));
  final parts = <PostTextPart>[];
  var index = 0;
  for (final (match, isTag) in matches) {
    if (match.start < index) continue;
    if (match.start > index) {
      parts.add(PostTextPart(body.substring(index, match.start)));
    }
    if (isTag) {
      parts.add(
          PostTextPart(match.group(0)!, tag: match.group(1)!.toLowerCase()));
      index = match.end;
    } else {
      final raw = match.group(1)!;
      final handle = _cleanHandle(raw);
      if (handle.isEmpty) {
        parts.add(PostTextPart(match.group(0)!));
        index = match.end;
        continue;
      }
      // Trailing punctuation ("@amal.") stays plain text.
      final end = match.start + 1 + handle.length;
      parts
          .add(PostTextPart(body.substring(match.start, end), mention: handle));
      index = end;
    }
  }
  if (index < body.length) parts.add(PostTextPart(body.substring(index)));
  return parts;
}

/// A parsed search box entry: `#tag`, `@handle` and free words.
class PostQuery {
  const PostQuery(
      {this.tags = const [], this.mentions = const [], this.words = const []});
  final List<String> tags;
  final List<String> mentions;
  final List<String> words;
  bool get isEmpty => tags.isEmpty && mentions.isEmpty && words.isEmpty;

  factory PostQuery.parse(String input) {
    final tags = <String>{};
    final mentions = <String>{};
    final words = <String>{};
    for (final token in input.trim().split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      if (token.startsWith('#')) {
        final tag = extractTags(token);
        if (tag.isNotEmpty) tags.add(tag.first);
      } else if (token.startsWith('@')) {
        final handle = extractMentions(token);
        if (handle.isNotEmpty) mentions.add(handle.first);
      } else {
        words.addAll(_wordPattern
            .allMatches(token.toLowerCase())
            .map((m) => m.group(0)!));
      }
    }
    return PostQuery(
        tags: tags.take(5).toList(),
        mentions: mentions.take(5).toList(),
        words: words.take(8).toList());
  }

  /// Number of times the free words start a word in [body]; used for ranking.
  int score(String body) {
    if (words.isEmpty) return 0;
    final bodyWords = _wordPattern
        .allMatches(body.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();
    var score = 0;
    for (final word in words) {
      for (final candidate in bodyWords) {
        if (candidate == word) {
          score += 3;
        } else if (candidate.startsWith(word)) {
          score += 1;
        }
      }
    }
    return score;
  }
}
