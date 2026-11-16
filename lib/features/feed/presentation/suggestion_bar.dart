import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/connectly_theme.dart';
import '../domain/feed_models.dart';
import 'feed_widgets.dart';

/// Watches [controller]; while the word at the cursor starts with `#` or `@`,
/// shows matching tags or people. Tapping one completes the word.
class SuggestionBar extends StatefulWidget {
  const SuggestionBar(
      {required this.controller, required this.repository, super.key});
  final TextEditingController controller;
  final FeedRepository repository;
  @override
  State<SuggestionBar> createState() => _SuggestionBarState();
}

class _SuggestionBarState extends State<SuggestionBar> {
  List<FeedSuggestion> _items = const [];
  String? _token;
  Timer? _debounce;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  /// The `#…`/`@…` word that ends at the cursor, with its start index.
  (String, int)? _currentToken() {
    final value = widget.controller.value;
    final cursor = value.selection.baseOffset;
    if (cursor < 0 || cursor > value.text.length) return null;
    final before = value.text.substring(0, cursor);
    final match = RegExp(r'(^|\s)([#@][^\s#@]{0,40})$').firstMatch(before);
    if (match == null) return null;
    return (match.group(2)!, cursor - match.group(2)!.length);
  }

  void _changed() {
    final token = _currentToken()?.$1;
    if (token == _token) return;
    _token = token;
    _debounce?.cancel();
    if (token == null) {
      if (_items.isNotEmpty) setState(() => _items = const []);
      return;
    }
    final request = ++_request;
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      try {
        final items = await widget.repository.suggestions(token);
        if (mounted && request == _request) setState(() => _items = items);
      } catch (_) {
        if (mounted && request == _request) setState(() => _items = const []);
      }
    });
  }

  void _apply(FeedSuggestion item) {
    final token = _currentToken();
    if (token == null) return;
    final (word, start) = token;
    final text = widget.controller.text;
    final end = start + word.length;
    final insert = '${item.value} ';
    final next = text.replaceRange(start, end, insert);
    _request++;
    _token = null;
    setState(() => _items = const []);
    widget.controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: start + insert.length));
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty || _token == null) return const SizedBox.shrink();
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final item = _items[i];
          return ActionChip(
            key: Key('suggest_${item.value}'),
            onPressed: () => _apply(item),
            backgroundColor: ConnectlyTheme.surface,
            label: Text.rich(TextSpan(children: [
              TextSpan(
                  text: item.value,
                  style: const TextStyle(
                      color: ConnectlyTheme.yellow,
                      fontWeight: FontWeight.w600)),
              TextSpan(
                  text: '  ${item.label}',
                  style: const TextStyle(color: feedMuted, fontSize: 12)),
            ])),
          );
        },
      ),
    );
  }
}
