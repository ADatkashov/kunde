class PlatformSnapshot {
  const PlatformSnapshot({
    required this.releaseStage,
    required this.marketplaceEnabled,
    required this.oidcIssuerConfigured,
    required this.aiEnabled,
    this.bookingEnabled = false,
    this.ridesEnabled = false,
    this.deliveryEnabled = false,
    this.deliverySyntheticRouting = false,
    this.autoEnabled = false,
    this.leisureEnabled = false,
    this.healthEnabled = false,
  });

  final String releaseStage;
  final bool marketplaceEnabled;
  final bool oidcIssuerConfigured;
  final bool aiEnabled;

  /// Service booking (barbershops) DEV pilot; absent on older servers.
  final bool bookingEnabled;
  final bool ridesEnabled;
  final bool deliveryEnabled;
  final bool deliverySyntheticRouting;

  /// KUNDE Auto DEV pilot; absent on older servers.
  final bool autoEnabled;
  final bool healthEnabled;

  /// KUNDE Leisure; on by default in DEV/TEST, decided by the server; absent on older servers.
  final bool leisureEnabled;

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
      ridesEnabled: json['ridesEnabled'] == true,
      deliveryEnabled: json['deliveryEnabled'] == true,
      deliverySyntheticRouting: json['deliverySyntheticRouting'] == true,
      autoEnabled: json['autoEnabled'] == true,
      leisureEnabled: json['leisureEnabled'] == true,
      healthEnabled: json['healthEnabled'] == true,
    );
  }
}
