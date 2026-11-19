import 'package:flutter/material.dart';

import '../core/theme.dart';

enum Tone { attention, progress, success, neutral, danger }

/// Colored status pill: icon + text (never color alone) for accessibility.
class StatusChip extends StatelessWidget {
  const StatusChip({required this.label, required this.tone, super.key});
  final String label;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final t = context.tones;
    final c = context.colors;
    final (bg, fg, icon) = switch (tone) {
      Tone.attention => (
          t.warningContainer,
          t.warning,
          Icons.notifications_active_rounded
        ),
      Tone.progress => (t.infoContainer, t.info, Icons.timelapse_rounded),
      Tone.success => (
          t.successContainer,
          t.success,
          Icons.check_circle_rounded
        ),
      Tone.danger => (c.errorContainer, c.error, Icons.cancel_rounded),
      Tone.neutral => (
          c.surfaceContainerHighest,
          c.onSurfaceVariant,
          Icons.circle_outlined
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 6),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(Radii.chip)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: fg),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelLarge?.copyWith(color: fg)),
        ),
      ]),
    );
  }
}

Tone orderTone(String status) => switch (status) {
      'PLACED' => Tone.attention,
      'ACCEPTED' || 'PREPARING' || 'ON_THE_WAY' => Tone.progress,
      'DELIVERED' => Tone.success,
      'CANCELLED' => Tone.danger,
      _ => Tone.neutral,
    };

Tone bookingTone(String status) => switch (status) {
      'PENDING' || 'REQUESTED' => Tone.attention,
      'CONFIRMED' || 'CHECKED_IN' || 'IN_PROGRESS' => Tone.progress,
      'COMPLETED' => Tone.success,
      'CANCELLED' || 'REJECTED' || 'NO_SHOW' => Tone.danger,
      _ => Tone.neutral,
    };
