import 'package:flutter/material.dart';

import 'package:kunde_auth/auth_repository.dart';
import 'package:kunde_ui/ride_strings.dart';

class AdminEmployeeScreen extends StatefulWidget {
  const AdminEmployeeScreen({required this.auth, super.key});

  final AuthRepository auth;

  @override
  State<AdminEmployeeScreen> createState() => _AdminEmployeeScreenState();
}

class _AdminEmployeeScreenState extends State<AdminEmployeeScreen> {
  late Future<Map<String, dynamic>> _page = _load();
  String? _after;
  final _previous = <String?>[];

  Future<Map<String, dynamic>> _load() async {
    final uri = Uri(
      path: 'admin/employees',
      queryParameters: _after == null ? null : {'after': _after},
    );
    return await widget.auth.authorizedJson('GET', uri.toString())
        as Map<String, dynamic>;
  }

  void _go(String? after) {
    setState(() {
      _after = after;
      _page = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = RideStrings(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('Сотрудники', 'Қызметкерлер', 'Employees')),
      ),
      body: SafeArea(
        child: FutureBuilder(
          future: _page,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(s.error),
                      TextButton(
                          onPressed: () => _go(_after), child: Text(s.retry)),
                    ],
                  ),
                ),
              );
            }
            final page = snapshot.requireData;
            final employees =
                (page['employees'] as List).cast<Map<String, dynamic>>();
            final next = page['next'] as String?;
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (employees.isEmpty)
                      Text(s.t('Сотрудников нет', 'Қызметкерлер жоқ',
                          'No employees')),
                    for (final employee in employees)
                      Card(
                        child: ListTile(
                          title: Text(employee['displayName'] as String? ??
                              employee['id'] as String),
                          subtitle: Text(employee['hasAccess'] == true
                              ? s.t('Доступ действует',
                                  'Қолжетімділік белсенді', 'Access active')
                              : s.t(
                                  'Доступ не действует',
                                  'Қолжетімділік белсенді емес',
                                  'Access inactive')),
                        ),
                      ),
                    if (_previous.isNotEmpty || next != null)
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 12,
                        children: [
                          TextButton(
                            onPressed: _previous.isEmpty
                                ? null
                                : () => _go(_previous.removeLast()),
                            child: Text(s.back),
                          ),
                          FilledButton(
                            onPressed: next == null
                                ? null
                                : () {
                                    _previous.add(_after);
                                    _go(next);
                                  },
                            child: Text(s.t('Следующая страница', 'Келесі бет',
                                'Next page')),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
