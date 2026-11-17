import 'package:flutter/material.dart';

import '../../app/ops_store.dart';
import '../../core/error_text.dart';
import '../../core/strings.dart';
import '../../data/models.dart';
import '../../widgets/dialogs.dart';

/// Confirms and performs a booking action offered by the server in
/// `allowedActions`. REJECT and CANCEL need a written reason.
Future<bool> performBookingAction(
  BuildContext context,
  OpsStore store,
  PartnerBooking booking,
  String action,
) async {
  final s = S.of(context);
  String? reason;
  if (action == 'REJECT' || action == 'CANCEL') {
    reason = await reasonDialog(
      context,
      title: action == 'REJECT' ? s.rejectBookingTitle : s.cancelBookingTitle,
    );
    if (reason == null) return false;
  } else {
    final ok = await confirmDialog(context,
        title: s.bookingAction(action), body: s.bookingActionConfirm(action));
    if (!ok) return false;
  }
  if (!context.mounted) return false;
  try {
    final result =
        await store.changeBooking(booking.id, action, reason: reason);
    if (result == null) return false;
    if (context.mounted) showToast(context, s.bookingToast);
    return true;
  } on Object catch (e) {
    if (context.mounted) showToast(context, errorText(s, e), error: true);
    return false;
  }
}
