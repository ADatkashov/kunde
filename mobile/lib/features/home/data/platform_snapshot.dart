class PlatformSnapshot {
  const PlatformSnapshot({
    required this.releaseStage,
    required this.marketplaceEnabled,
    required this.oidcIssuerConfigured,
    required this.aiEnabled,
    this.bookingEnabled = false,
    this.homeServicesEnabled = false,
    this.ridesEnabled = false,
    this.deliveryEnabled = false,
    this.deliverySyntheticRouting = false,
    this.autoEnabled = false,
    this.leisureEnabled = false,
    this.eventsEnabled = false,
    this.healthEnabled = false,
    this.educationEnabled = false,
    this.groceriesEnabled = false,
  });

  final String releaseStage;
  final bool marketplaceEnabled;
  final bool oidcIssuerConfigured;
  final bool aiEnabled;

  /// Service booking (barbershops) DEV pilot; absent on older servers.
  final bool bookingEnabled;
  final bool homeServicesEnabled;
  final bool ridesEnabled;
  final bool deliveryEnabled;
  final bool deliverySyntheticRouting;

  /// KUNDE Auto DEV pilot; absent on older servers.
  final bool autoEnabled;
  final bool healthEnabled;
  final bool educationEnabled;

  /// KUNDE Groceries switch (server decides). Older servers do not send it: Groceries then follows the marketplace.
  final bool groceriesEnabled;

  /// KUNDE Leisure; on by default in DEV/TEST, decided by the server; absent on older servers.
  final bool leisureEnabled;
  final bool eventsEnabled;

  factory PlatformSnapshot.fromJson(Map<String, dynamic> json) {
    final stage = json['releaseStage'];
    final marketplace = json['marketplaceEnabled'];
    final issuer = json['oidcIssuerConfigured'];
    final ai = json['aiEnabled'];
    if (stage is! String ||
        marketplace is! bool ||
        issuer is! bool ||
        ai is! bool) {
      throw const FormatException('Invalid platform capability response');
    }
    return PlatformSnapshot(
      releaseStage: stage,
      marketplaceEnabled: marketplace,
      oidcIssuerConfigured: issuer,
      aiEnabled: ai,
      bookingEnabled: json['bookingEnabled'] == true,
      homeServicesEnabled: json['homeServicesEnabled'] == true,
      ridesEnabled: json['ridesEnabled'] == true,
      deliveryEnabled: json['deliveryEnabled'] == true,
      deliverySyntheticRouting: json['deliverySyntheticRouting'] == true,
      autoEnabled: json['autoEnabled'] == true,
      leisureEnabled: json['leisureEnabled'] == true,
      eventsEnabled: json['eventsEnabled'] == true,
      healthEnabled: json['healthEnabled'] == true,
      educationEnabled: json['educationEnabled'] == true,
      groceriesEnabled: json.containsKey('groceriesEnabled')
          ? json['groceriesEnabled'] == true
          : marketplace,
    );
  }
}
