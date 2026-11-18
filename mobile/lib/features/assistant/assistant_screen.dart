import 'package:flutter/material.dart';

import '../../core/localization/kunde_localizations.dart';
import '../home/presentation/home_strings.dart';
import '../home/presentation/super_app_widgets.dart';

typedef AssistantMessage = ({String text, bool isUser});

/// Adapter seam for an approved API. The current backend has no chat route.
abstract interface class AssistantGateway {
  Future<List<AssistantMessage>> history();
  Future<String> send(String message);
}

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({this.gateway, super.key});

  final AssistantGateway? gateway;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _draft = TextEditingController();
  List<AssistantMessage> _messages = [];
  bool _loading = false;
  bool _historyFailed = false;
  bool _sendFailed = false;

  @override
  void initState() {
    super.initState();
    if (widget.gateway != null) _load();
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _historyFailed = false;
    });
    try {
      final history = await widget.gateway!.history();
      if (!mounted) return;
      setState(() => _messages = List.of(history));
    } on Exception {
      if (mounted) setState(() => _historyFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final gateway = widget.gateway;
    final text = _draft.text.trim();
    if (gateway == null || _loading || _historyFailed || text.isEmpty) return;
    setState(() {
      _loading = true;
      _sendFailed = false;
      _messages.add((text: text, isUser: true));
    });
    _draft.clear();
    try {
      final answer = await gateway.send(text);
      if (mounted) setState(() => _messages.add((text: answer, isUser: false)));
    } on Exception {
      if (!mounted) return;
      setState(() {
        _messages.removeLast();
        _draft.text = text;
        _sendFailed = true;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = KundeLocalizations.of(context);
    final theme = Theme.of(context);
    final connected = widget.gateway != null;
    final canSend = connected && !_loading && !_historyFailed;
    return Scaffold(
      appBar: AppBar(title: Text(s.homeAiTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: kundeHeroGradient,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              color: Colors.white,
                              size: 40,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              connected
                                  ? s.assistantPrompt
                                  : s.homeAiUnavailable,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (connected && _messages.isEmpty && !_historyFailed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final prompt in s.assistantSuggestions)
                                ActionChip(
                                  label: Text(prompt),
                                  onPressed: canSend
                                      ? () => _draft.text = prompt
                                      : null,
                                ),
                            ],
                          ),
                        ),
                      for (final message in _messages)
                        Align(
                          alignment: message.isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Card(
                            color: message.isUser
                                ? theme.colorScheme.primaryContainer
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Text(message.text),
                            ),
                          ),
                        ),
                      if (_historyFailed || _sendFailed)
                        EmptyStateCard(
                          icon: Icons.error_outline,
                          title: s.offline,
                          body: s.retryHint,
                        ),
                      if (_historyFailed)
                        TextButton(onPressed: _load, child: Text(s.retry)),
                    ],
                  ),
                ),
                if (_loading) const LinearProgressIndicator(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: TextField(
                    controller: _draft,
                    enabled: canSend,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: s.assistantMessage,
                      suffixIcon: IconButton(
                        onPressed: canSend ? _send : null,
                        tooltip: s.assistantSend,
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
