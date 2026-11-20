import '../../data/partner_api.dart';

/// Leisure endpoints of one partner (`/partner/partners/{id}/leisure/...`). Roles, ownership, prices and ticket rules are decided by the server;
/// this class only moves JSON.
class LeisureOps {
  const LeisureOps(this.api, this.partnerId);

  final PartnerApi api;
  final String partnerId;

  String get _root =>
      'partner/partners/${Uri.encodeComponent(partnerId)}/leisure';

  Future<Map<String, dynamic>> stats(int days) =>
      api.getMap('$_root/stats?days=$days');
  Future<List<Map<String, dynamic>>> venues() => api.getList('$_root/venues');
  Future<Map<String, dynamic>> createVenue(Map<String, dynamic> body) =>
      api.postMap('$_root/venues', body);
  Future<Map<String, dynamic>> updateVenue(
          String id, Map<String, dynamic> venue, int version) =>
      api.putMap('$_root/venues/$id', {'venue': venue, 'version': version});
  Future<Map<String, dynamic>> submitVenue(String id) =>
      api.postMap('$_root/venues/$id/submit', {});
  Future<List<Map<String, dynamic>>> events() => api.getList('$_root/events');
  Future<Map<String, dynamic>> createEvent(
          String venueId, Map<String, dynamic> body) =>
      api.postMap('$_root/venues/$venueId/events', body);
  Future<Map<String, dynamic>> updateEvent(
          String id, Map<String, dynamic> event, int version) =>
      api.putMap('$_root/events/$id', {'event': event, 'version': version});
  Future<Map<String, dynamic>> submitEvent(String id) =>
      api.postMap('$_root/events/$id/submit', {});
  Future<Map<String, dynamic>> archiveEvent(String id) =>
      api.postMap('$_root/events/$id/archive', {});
  Future<List<Map<String, dynamic>>> ticketTypes(String eventId) =>
      api.getList('$_root/events/$eventId/ticket-types');
  Future<Map<String, dynamic>> saveTicketType(
          String eventId, String? id, Map<String, dynamic> body) =>
      id == null
          ? api.postMap('$_root/events/$eventId/ticket-types', body)
          : api.putMap('$_root/events/$eventId/ticket-types/$id', body);
  Future<List<Map<String, dynamic>>> sessions(String eventId,
          {bool past = false}) =>
      api.getList('$_root/events/$eventId/sessions?past=$past&limit=50');
  Future<List<Map<String, dynamic>>> createSessions(
      String eventId, Map<String, dynamic> body) async {
    final r = await api.postJson('$_root/events/$eventId/sessions', body);
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> cancelSession(String id, String reason) =>
      api.postMap('$_root/sessions/$id/cancel', {'reason': reason});
  Future<List<Map<String, dynamic>>> assignments(String sessionId) =>
      api.getList('$_root/sessions/$sessionId/assignments');
  Future<Map<String, dynamic>> assign(
          String sessionId, Map<String, dynamic> body) =>
      api.postMap('$_root/sessions/$sessionId/assignments', body);
  Future<Map<String, dynamic>> cancelAssignment(String id) =>
      api.postMap('$_root/assignments/$id/cancel', {});
  Future<List<Map<String, dynamic>>> orders(String scope) =>
      api.getList('$_root/orders?scope=$scope&limit=50');
  Future<Map<String, dynamic>> orderAction(String id, String action,
          {String? reason}) =>
      api.postMap('$_root/orders/$id/action',
          {'action': action, if (reason != null) 'reason': reason});
  Future<Map<String, dynamic>> checkin(String code) =>
      api.postMap('$_root/checkins', {'code': code});
  Future<List<Map<String, dynamic>>> checkins() =>
      api.getList('$_root/checkins?limit=20');
  Future<List<Map<String, dynamic>>> history() =>
      api.getList('$_root/history?limit=50');
}
