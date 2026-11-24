import 'dart:async';

import 'package:flutter/widgets.dart';

/// Rebuilds [builder] with the current time every [every]; used for
/// countdowns. The timer stops when the widget leaves the tree.
class NowBuilder extends StatefulWidget {
  const NowBuilder({
    required this.builder,
    this.every = const Duration(seconds: 15),
    super.key,
  });
  final Widget Function(BuildContext context, DateTime now) builder;
  final Duration every;
  @override
  State<NowBuilder> createState() => _NowBuilderState();
}

class _NowBuilderState extends State<NowBuilder> {
  late DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.every, (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}
