import 'package:flutter/material.dart';

import '../../food/presentation/food_widgets.dart';
import '../booking_services.dart';
import 'venue_list_screen.dart';

/// «Услуги»: service categories. Barbershops are live in the DEV pilot; other categories are announced honestly.
class ServicesHomeScreen extends StatelessWidget {
  const ServicesHomeScreen({required this.services, super.key});

  final BookingServices services;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Услуги · Алматы')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text('Запишитесь онлайн', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('Выберите заведение, мастера и удобное время.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            _CategoryCard(
              emoji: '✂️',
              tone: 'blue',
              title: 'Барбершопы',
              subtitle: 'Стрижки, борода, бритьё',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => VenueListScreen(services: services))),
            ),
            const SizedBox(height: 12),
            _CategoryCard(
              emoji: '🧹',
              tone: 'green',
              title: 'Уборка',
              subtitle: 'Появится после запуска барбершопов',
              soon: true,
              onTap: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (context) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Уборка — скоро',
                              style: theme.textTheme.titleLarge),
                          const SizedBox(height: 8),
                          const Text(
                              'Запись на уборку и другие бытовые услуги появится после запуска барбершопов.'),
                          const SizedBox(height: 16),
                          Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Понятно'))),
                        ]),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
                'DEV-режим: заведения и мастера синтетические, запись подтверждается автоматически, оплата на месте.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard(
      {required this.emoji,
      required this.tone,
      required this.title,
      required this.subtitle,
      required this.onTap,
      this.soon = false});

  final String emoji;
  final String tone;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool soon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: theme.colorScheme.outlineVariant)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Opacity(
          opacity: soon ? 0.65 : 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              EmojiTile(emoji: emoji, tone: tone, size: 64, radius: 18),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ]),
              ),
              if (soon)
                const Chip(label: Text('Скоро'))
              else
                const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      ),
    );
  }
}
