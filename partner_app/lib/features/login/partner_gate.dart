import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/states.dart';

/// Several approved businesses are linked to the phone: the user picks one.
class ChoosePartnerScreen extends StatelessWidget {
  const ChoosePartnerScreen({required this.controller, super.key});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final revoked = controller.notice == SignOutNotice.accessRevoked;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.choosePartnerTitle),
        actions: [
          IconButton(
            tooltip: s.logout,
            icon: const Icon(Icons.logout_rounded),
            onPressed: controller.logout,
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(Gap.lg), children: [
        if (revoked)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.lg),
            child: Text(s.accessRevokedBody, style: context.text.bodyMedium),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.lg),
            child:
                Text(s.choosePartnerSubtitle, style: context.text.bodyMedium),
          ),
        for (final p in controller.partners)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                minVerticalPadding: Gap.md,
                leading: CircleAvatar(
                  backgroundColor: context.colors.primaryContainer,
                  child: Icon(Icons.storefront_rounded,
                      color: context.colors.onPrimaryContainer),
                ),
                title: Text(p.name.isEmpty ? s.navBusiness : p.name,
                    style: context.text.titleMedium),
                subtitle: Text(s.role(p.role)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  controller.clearNotice();
                  controller.select(p);
                },
              ),
            ),
          ),
      ]),
    );
  }
}

/// Signed in, but the server reports no approved partner for this account.
class NoAccessScreen extends StatelessWidget {
  const NoAccessScreen({required this.controller, super.key});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final revoked = controller.notice == SignOutNotice.accessRevoked;
    return Scaffold(
      body: SafeArea(
        child: MessageView(
          icon: Icons.lock_outline_rounded,
          title: revoked ? s.accessRevokedTitle : s.noPartnerTitle,
          body: revoked ? s.accessRevokedBody : s.noPartnerBody,
          actionLabel: s.logout,
          onAction: controller.logout,
        ),
      ),
    );
  }
}

/// A stored session exists but the API could not be reached on start-up.
class UnreachableScreen extends StatelessWidget {
  const UnreachableScreen({required this.controller, super.key});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      body: SafeArea(
        child: MessageView(
          icon: Icons.wifi_off_rounded,
          title: s.errNetworkTitle,
          body: s.errNetworkBody,
          actionLabel: s.retry,
          onAction: controller.retryRestore,
        ),
      ),
    );
  }
}
