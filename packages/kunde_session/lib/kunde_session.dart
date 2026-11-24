/// Shared token-session core for the four KUNDE apps (ADR-024). Role-specific adapters supply persistence and the
/// refresh call; this package owns the lifecycle.
library;

export 'src/errors.dart';
export 'src/models.dart';
export 'src/ports.dart';
export 'src/secure_storage.dart';
export 'src/token_session.dart';
