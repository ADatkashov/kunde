import 'package:flutter/material.dart';

import '../core/theme.dart';

/// "Title … trailing" row that stacks vertically when the user enlarges the
/// system font, so nothing overflows at 200% text scale.
class HeaderRow extends StatelessWidget {
  const HeaderRow({required this.leading, required this.trailing, super.key});
  final Widget leading;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    if (scale > 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [leading, const SizedBox(height: Gap.sm), trailing],
      );
    }
    return Row(children: [
      Expanded(
          child: Align(
              alignment: AlignmentDirectional.centerStart, child: leading)),
      const SizedBox(width: Gap.sm),
      trailing,
    ]);
  }
}
