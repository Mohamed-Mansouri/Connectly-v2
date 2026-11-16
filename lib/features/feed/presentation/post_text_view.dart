import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../app/connectly_theme.dart';
import '../domain/post_text.dart';

/// Post body with tappable #tags and @mentions; optional search highlights.
class PostTextView extends StatefulWidget {
  const PostTextView(this.body,
      {this.onTag, this.onMention, this.highlight = const [], super.key});
  final String body;
  final ValueChanged<String>? onTag;
  final ValueChanged<String>? onMention;

  /// Lower-case word prefixes to mark, e.g. the words of a search query.
  final List<String> highlight;

  @override
  State<PostTextView> createState() => _PostTextViewState();
}

class _PostTextViewState extends State<PostTextView> {
  final _recognizers = <TapGestureRecognizer>[];

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  TapGestureRecognizer? _tap(VoidCallback? action) {
    if (action == null) return null;
    final recognizer = TapGestureRecognizer()..onTap = action;
    _recognizers.add(recognizer);
    return recognizer;
  }

  /// Splits plain text so words starting with a highlighted prefix stand out.
  List<InlineSpan> _plain(String text) {
    if (widget.highlight.isEmpty) return [TextSpan(text: text)];
    final spans = <InlineSpan>[];
    var index = 0;
    for (final m in RegExp(r'[\p{L}\p{N}_]+', unicode: true).allMatches(text)) {
      final word = m.group(0)!.toLowerCase();
      if (!widget.highlight.any(word.startsWith)) continue;
      if (m.start > index) {
        spans.add(TextSpan(text: text.substring(index, m.start)));
      }
      spans.add(TextSpan(
          text: m.group(0),
          style: TextStyle(
              backgroundColor: ConnectlyTheme.yellow.withValues(alpha: .28),
              fontWeight: FontWeight.w700)));
      index = m.end;
    }
    if (index < text.length) spans.add(TextSpan(text: text.substring(index)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();
    const link =
        TextStyle(color: ConnectlyTheme.yellow, fontWeight: FontWeight.w600);
    return Text.rich(
      TextSpan(children: [
        for (final part in splitPostText(widget.body))
          if (part.tag != null)
            TextSpan(
                text: part.text,
                style: link,
                recognizer: _tap(widget.onTag == null
                    ? null
                    : () => widget.onTag!(part.tag!)))
          else if (part.mention != null)
            TextSpan(
                text: part.text,
                style: link,
                recognizer: _tap(widget.onMention == null
                    ? null
                    : () => widget.onMention!(part.mention!)))
          else
            ..._plain(part.text),
      ]),
      style: const TextStyle(fontSize: 16, height: 1.55),
    );
  }
}
