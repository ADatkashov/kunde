import 'package:flutter/material.dart';

import '../../core/error_text.dart';
import '../../core/strings.dart';
import '../../data/partner_api.dart';

class HomeServicesAssignmentsScreen extends StatefulWidget {
  const HomeServicesAssignmentsScreen(
      {required this.api,
      required this.partnerId,
      required this.canManage,
      super.key});

  final PartnerApi api;
  final String partnerId;
  final bool canManage;

  @override
  State<HomeServicesAssignmentsScreen> createState() =>
      _HomeServicesAssignmentsScreenState();
}

class _HomeServicesAssignmentsScreenState
    extends State<HomeServicesAssignmentsScreen> {
  String get _root =>
      'partner/partners/${Uri.encodeComponent(widget.partnerId)}/home-services/assignments';
  late Future<List<Map<String, dynamic>>> _orders = widget.api.getList(_root);
  bool _busy = false;

  String _t(String ru, String kk, String en) =>
      switch (Localizations.localeOf(context).languageCode) {
        'kk' => kk,
        'en' => en,
        _ => ru,
      };

  Future<void> _reload() async {
    setState(() => _orders = widget.api.getList(_root));
    try {
      await _orders;
    } catch (_) {
      // The list handles the error and offers retry.
    }
  }

  Future<void> _assign(Map<String, dynamic> order) async {
    final path = '$_root/${order['id']}';
    setState(() => _busy = true);
    try {
      final masters = await widget.api.getList('$path/masters');
      if (!mounted) return;
      if (masters.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_t('Нет подходящих мастеров', 'Сәйкес шеберлер жоқ',
              'No eligible masters')),
        ));
        return;
      }
      final form = GlobalKey<FormState>();
      String? masterId;
      var reason = '';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
              _t('Назначить мастера', 'Шеберді тағайындау', 'Assign a master')),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  items: [
                    for (final master in masters)
                      DropdownMenuItem(
                        value: master['id'] as String,
                        child: Text(master['name'] as String),
                      ),
                  ],
                  onChanged: (value) => masterId = value,
                  validator: (value) => value == null
                      ? _t('Выберите мастера', 'Шеберді таңдаңыз',
                          'Select a master')
                      : null,
                ),
                TextFormField(
                  maxLength: 200,
                  decoration: InputDecoration(
                      labelText: _t('Причина', 'Себеп', 'Reason')),
                  onChanged: (value) => reason = value.trim(),
                  validator: (_) => reason.isEmpty
                      ? _t('Укажите причину', 'Себебін көрсетіңіз',
                          'Enter a reason')
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(S.of(context).back),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: Text(_t('Назначить', 'Тағайындау', 'Assign')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await widget.api.postJson(path, {
        'masterId': masterId,
        'expectedVersion': order['version'],
        'reason': reason,
      });
      if (mounted) await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorText(S.of(context), error))),
      );
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_t('Ожидают назначения', 'Тағайындау күтілуде',
              'Awaiting assignment')),
        ),
        body: SafeArea(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _orders,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(errorText(S.of(context), snapshot.error!)),
                      TextButton(
                          onPressed: _reload, child: Text(S.of(context).retry)),
                    ],
                  ),
                );
              }
              final orders = snapshot.data!;
              return RefreshIndicator(
                onRefresh: _reload,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (orders.isEmpty)
                      Text(_t(
                          'Все заказы назначены',
                          'Барлық тапсырыс тағайындалған',
                          'No unassigned jobs')),
                    for (final order in orders)
                      Card(
                        child: ListTile(
                          title: Text(order['serviceName'] as String),
                          subtitle: Text(order['bookingNumber'] as String),
                          trailing: widget.canManage
                              ? IconButton(
                                  tooltip: _t('Назначить мастера',
                                      'Шеберді тағайындау', 'Assign a master'),
                                  onPressed:
                                      _busy ? null : () => _assign(order),
                                  icon: const Icon(Icons.person_add_alt),
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      );
}
