import 'package:flutter/material.dart';

import '../core/error_text.dart';
import '../core/strings.dart';
import '../core/theme.dart';

/// Pulsing placeholder block used by skeleton screens.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({this.height = 16, this.width, this.radius = 8, super.key});
  final double height;
  final double? width;
  final double radius;
  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.colors.onSurface;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color:
                base.withValues(alpha: reduce ? 0.10 : 0.06 + 0.06 * _c.value),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}

/// Skeleton of a record card; [count] of them stand in for a loading list.
class SkeletonList extends StatelessWidget {
  const SkeletonList({this.count = 4, super.key});
  final int count;
  @override
  Widget build(BuildContext context) => Semantics(
        label: S.of(context).pleaseWait,
        child: ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Gap.lg),
          itemCount: count,
          separatorBuilder: (_, __) => const SizedBox(height: Gap.md),
          itemBuilder: (_, __) => const Card(
            child: Padding(
              padding: EdgeInsets.all(Gap.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(height: 18, width: 180),
                  SizedBox(height: Gap.md),
                  SkeletonBox(height: 12),
                  SizedBox(height: Gap.sm),
                  SkeletonBox(height: 12, width: 120),
                  SizedBox(height: Gap.lg),
                  SkeletonBox(height: 44, radius: 14),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Centered illustration + title + body (+ optional action).
class MessageView extends StatelessWidget {
  const MessageView({
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    super.key,
  });
  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Gap.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ExcludeSemantics(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: context.colors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon,
                      size: 34, color: context.colors.onPrimaryContainer),
                ),
              ),
              const SizedBox(height: Gap.lg),
              Text(title,
                  textAlign: TextAlign.center, style: context.text.titleLarge),
              if (body != null) ...[
                const SizedBox(height: Gap.sm),
                Text(body!,
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium
                        ?.copyWith(color: context.colors.onSurfaceVariant)),
              ],
              if (onAction != null && actionLabel != null) ...[
                const SizedBox(height: Gap.lg),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ]),
          ),
        ),
      );
}

/// Error state with a retry button; text is always human readable.
class ErrorView extends StatelessWidget {
  const ErrorView({required this.error, required this.onRetry, super.key});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final offline = isOffline(error);
    return MessageView(
      icon: offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      title: offline ? s.errNetworkTitle : s.errLoad,
      body: errorText(s, error),
      actionLabel: s.retry,
      onAction: onRetry,
    );
  }
}

/// Slim banner shown above stale data when a background refresh failed.
class StaleBanner extends StatelessWidget {
  const StaleBanner({required this.error, super.key});
  final Object error;
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final tones = context.tones;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: tones.warningContainer,
        padding:
            const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
        child: Row(children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: tones.warning),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
                isOffline(error) ? s.offlineBanner : errorText(s, error),
                style: context.text.bodySmall
                    ?.copyWith(color: context.colors.onSurface)),
          ),
        ]),
      ),
    );
  }
}
