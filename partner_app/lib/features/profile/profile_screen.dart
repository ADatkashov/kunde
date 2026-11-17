import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/settings.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/dialogs.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen(
      {required this.controller, required this.settings, super.key});
  final AppController controller;
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final partner = controller.partner;
    return Scaffold(
      appBar: AppBar(title: Text(s.profileTitle)),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) =>
            ListView(padding: const EdgeInsets.all(Gap.lg), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: context.colors.primaryContainer,
                  child: Icon(Icons.storefront_rounded,
                      size: 28, color: context.colors.onPrimaryContainer),
                ),
                const SizedBox(width: Gap.lg),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(partner?.name ?? s.navBusiness,
                            style: context.text.titleLarge),
                        const SizedBox(height: 2),
                        Text('${s.yourRole}: ${s.role(partner?.role ?? '')}',
                            style: context.text.bodyMedium?.copyWith(
                                color: context.colors.onSurfaceVariant)),
                      ]),
                ),
              ]),
            ),
          ),
          if (controller.partners.length > 1) ...[
            const SizedBox(height: Gap.md),
            OutlinedButton.icon(
              onPressed: controller.switchPartner,
              icon: const Icon(Icons.swap_horiz_rounded),
              label: Text(s.switchPartner),
            ),
          ],
          const SizedBox(height: Gap.xl),
          Text(s.language, style: context.text.titleSmall),
          const SizedBox(height: Gap.sm),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                  value: 'auto',
                  label: Text(s.languageAuto, overflow: TextOverflow.ellipsis)),
              const ButtonSegment(value: 'ru', label: Text('RU')),
              const ButtonSegment(value: 'kk', label: Text('KK')),
              const ButtonSegment(value: 'en', label: Text('EN')),
            ],
            selected: {settings.locale?.languageCode ?? 'auto'},
            onSelectionChanged: (v) =>
                settings.setLocale(v.first == 'auto' ? null : Locale(v.first)),
          ),
          const SizedBox(height: Gap.xl),
          Text(s.theme, style: context.text.titleSmall),
          const SizedBox(height: Gap.sm),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                  value: ThemeMode.system,
                  label: Text(s.themeSystem, overflow: TextOverflow.ellipsis)),
              ButtonSegment(
                  value: ThemeMode.light,
                  label: Text(s.themeLight, overflow: TextOverflow.ellipsis)),
              ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text(s.themeDark, overflow: TextOverflow.ellipsis)),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (v) => settings.setThemeMode(v.first),
          ),
          const SizedBox(height: Gap.xl),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: Text(s.notifications),
              subtitle: Text(s.notificationsNote),
            ),
          ),
          const SizedBox(height: Gap.md),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(s.about),
              subtitle: Text(s.devBuildNote),
            ),
          ),
          const SizedBox(height: Gap.xl),
          OutlinedButton.icon(
            style:
                OutlinedButton.styleFrom(foregroundColor: context.colors.error),
            onPressed: () async {
              final ok = await confirmDialog(context,
                  title: s.logout,
                  body: s.logoutConfirm,
                  confirmLabel: s.logout);
              if (ok) await controller.logout();
            },
            icon: const Icon(Icons.logout_rounded),
            label: Text(s.logout),
          ),
        ]),
      ),
    );
  }
}
