import 'package:flutter/material.dart';

import '../../app/ops_store.dart';
import '../../core/error_text.dart';
import '../../core/strings.dart';
import '../../data/models.dart';
import '../../widgets/dialogs.dart';

/// Confirms and performs one order transition. The set of allowed statuses
/// always comes from the server (`allowedNext`); a rejection or conflict is
/// shown as plain text and the lists are refreshed by the store.
Future<bool> performOrderAction(
  BuildContext context,
  OpsStore store,
  PartnerOrder order,
  String status,
) async {
  final s = S.of(context);
  String? reason;
  if (status == 'CANCELLED') {
    reason = await reasonDialog(
      context,
      title: s.cancelOrderTitle,
      suggestions: [s.reasonQuick1, s.reasonQuick2, s.reasonQuick3],
    );
    if (reason == null) return false;
  } else {
    final ok = await confirmDialog(context,
        title: s.orderAction(status), body: s.orderActionConfirm(status));
    if (!ok) return false;
  }
  if (!context.mounted) return false;
  try {
    final result = await store.changeOrder(order.id, status, reason: reason);
    if (result == null) return false; // already in flight
    if (context.mounted) showToast(context, s.orderConfirmedToast);
    return true;
  } on Object catch (e) {
    if (context.mounted) showToast(context, errorText(s, e), error: true);
    return false;
  }
}
