import 'package:flutter/material.dart';

import '../booking/booking_services.dart';
import 'package:kunde_models/booking_models.dart';
import '../booking/presentation/booking_flow_screen.dart';
import 'package:kunde_ui/booking_strings.dart';

class HealthSpecialistScreen extends StatelessWidget {
  const HealthSpecialistScreen({
    required this.services,
    required this.detail,
    required this.specialist,
    super.key,
  });

  final BookingServices services;
  final VenueDetail detail;
  final BookingMaster specialist;

  @override
  Widget build(BuildContext context) {
    final s = bkL10n(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final offered = detail.services.where(
      (service) =>
          service.available && specialist.serviceIds.contains(service.id),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(s.healthText('Специалист', 'Маман', 'Specialist')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: colors.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 40,
                        color: colors.onPrimaryContainer,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        specialist.name,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                      if (specialist.bio.isNotEmpty)
                        Text(
                          specialist.bio,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                      if (detail.venue.synthetic) ...[
                        const SizedBox(height: 8),
                        Text(
                          s.healthText(
                            'Синтетический профиль',
                            'Синтетикалық профиль',
                            'Synthetic profile',
                          ),
                          style: TextStyle(color: colors.onPrimaryContainer),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(detail.venue.name),
                subtitle: Text(detail.venue.addressText),
              ),
              const SizedBox(height: 16),
              Text(s.bkServices, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              if (offered.isEmpty) Text(s.bkUnavailable),
              for (final service in offered)
                Card(
                  child: ListTile(
                    title: Text(s.bkCatalogName(service.name)),
                    subtitle: Text(formatTenge(service.priceMinor)),
                    trailing: const Icon(Icons.calendar_month_outlined),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => BookingFlowScreen(
                          services: services,
                          detail: detail,
                          service: service,
                          initialMasterId: specialist.id,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
