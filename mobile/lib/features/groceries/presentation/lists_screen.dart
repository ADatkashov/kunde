import 'package:flutter/material.dart';

import '../../food/data/food_models.dart';
import '../../food/presentation/food_widgets.dart';
import '../data/groceries_api.dart';
import '../data/groceries_models.dart';
import '../data/groceries_services.dart';
import 'grocery_widgets.dart';
import 'groceries_strings.dart';
import 'product_screen.dart';

String _error(Object error, GStr s) =>
    error is GroceriesException ? error.messageFor(s.language) : s.retry;

Future<String?> _askName(BuildContext context, String title, String initial) {
  final s = GStr.of(context);
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 60,
        decoration: InputDecoration(labelText: s.listName),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
        FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(s.create)),
      ],
    ),
  );
}

/// The customer's shopping lists, stored on the server.
class ListsScreen extends StatefulWidget {
  const ListsScreen({required this.services, super.key});

  final GroceriesServices services;

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  late Future<List<GroceryListSummary>> _future = widget.services.api.lists();

  GroceriesServices get _services => widget.services;

  void _reload() => setState(() {
        _future = _services.api.lists();
      });

  Future<void> _create() async {
    final s = GStr.of(context);
    final name = await _askName(context, s.newList, '');
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final created = await _services.api.createList(name);
      if (!mounted) return;
      _reload();
      await _open(created);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_error(error, s))));
      }
    }
  }

  Future<void> _open(GroceryListSummary list) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ListDetailScreen(services: _services, list: list),
    ));
    if (mounted) _reload();
  }

  Future<void> _rename(GroceryListSummary list) async {
    final s = GStr.of(context);
    final name = await _askName(context, s.rename, list.name);
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await _services.api.renameList(list.id, name);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_error(error, s))));
      }
    }
  }

  Future<void> _delete(GroceryListSummary list) async {
    final s = GStr.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${s.delete}: ${list.name}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.delete)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _services.api.deleteList(list.id);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_error(error, s))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = GStr.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.myLists)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(s.newList),
      ),
      bottomNavigationBar: FoodCartBar(services: _services.food),
      body: FutureBuilder<List<GroceryListSummary>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Column(children: [
                SkeletonBox(height: 72, radius: 18),
                SizedBox(height: 12),
                SkeletonBox(height: 72, radius: 18),
              ]),
            );
          }
          if (snapshot.hasError) {
            return GroceryMessage(
              icon: Icons.cloud_off_outlined,
              title: _error(snapshot.error!, s),
              actionLabel: s.retry,
              onAction: _reload,
            );
          }
          final lists = snapshot.data!;
          if (lists.isEmpty) {
            return GroceryMessage(
              icon: Icons.checklist_rtl,
              title: s.emptyLists,
              body: s.emptyListsHint,
              actionLabel: s.newList,
              onAction: _create,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: lists.length,
            itemBuilder: (context, i) {
              final list = lists[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.checklist_rtl),
                  title: Text(list.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(s.listItems(list.items, list.checked)),
                  onTap: () => _open(list),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) =>
                        v == 'rename' ? _rename(list) : _delete(list),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'rename', child: Text(s.rename)),
                      PopupMenuItem(value: 'delete', child: Text(s.delete)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// One shopping list: tick bought items, change quantities, remove items and move the available ones to the cart.
class ListDetailScreen extends StatefulWidget {
  const ListDetailScreen(
      {required this.services, required this.list, super.key});

  final GroceriesServices services;
  final GroceryListSummary list;

  @override
  State<ListDetailScreen> createState() => _ListDetailScreenState();
}

class _ListDetailScreenState extends State<ListDetailScreen> {
  late Future<GroceryListDetail> _future =
      widget.services.api.list(widget.list.id);
  GroceryListDetail? _detail;
  bool _busy = false;

  GroceriesServices get _services => widget.services;

  void _reload() => setState(() {
        _future = _services.api.list(widget.list.id);
      });

  Future<void> _change(Future<GroceryListDetail> Function() action) async {
    final s = GStr.of(context);
    setState(() => _busy = true);
    try {
      final next = await action();
      if (mounted) setState(() => _detail = next);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_error(error, s))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toCart({bool replace = false}) async {
    final s = GStr.of(context);
    setState(() => _busy = true);
    try {
      final result =
          await _services.api.listToCart(widget.list.id, replace: replace);
      // The server cart changed: load it into the in-app cart so the cart screen and the server agree.
      await _services.cartSync.reloadFromServer(_services.storeFor);
      if (!mounted) return;
      setState(() => _busy = false);
      if (result.skipped.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(s.skippedTitle),
            content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in result.skipped)
                    Text('• ${item.name} — ${switch (item.reason) {
                      'UNAVAILABLE' => s.reasonUnavailable,
                      'ALREADY_BOUGHT' => s.reasonBought,
                      'OTHER_STORE' => s.reasonOtherStore,
                      _ => s.reasonCartFull,
                    }}'),
                ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'))
            ],
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.added)));
      }
    } on GroceriesException catch (error) {
      if (error.failure == GroceriesFailure.storeConflict && mounted) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(s.cartConflictTitle),
            content: Text(s.cartConflictBody),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(s.cancel)),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(s.replaceCart)),
            ],
          ),
        );
        if (ok == true && mounted) {
          setState(() => _busy = false);
          return _toCart(replace: true);
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.messageFor(s.language))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = GStr.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.list.name)),
      bottomNavigationBar: FoodCartBar(services: _services.food),
      body: FutureBuilder<GroceryListDetail>(
        future: _future,
        builder: (context, snapshot) {
          final detail = _detail ?? snapshot.data;
          if (detail == null) {
            if (snapshot.hasError) {
              return GroceryMessage(
                icon: Icons.cloud_off_outlined,
                title: _error(snapshot.error!, s),
                actionLabel: s.retry,
                onAction: _reload,
              );
            }
            return const Padding(
                padding: EdgeInsets.all(16),
                child: SkeletonBox(height: 72, radius: 18));
          }
          if (detail.items.isEmpty) {
            return GroceryMessage(
                icon: Icons.shopping_basket_outlined, title: s.listEmpty);
          }
          return Column(children: [
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: detail.items.length,
                itemBuilder: (context, i) => _ItemTile(
                  item: detail.items[i],
                  busy: _busy,
                  onChecked: (checked) => _change(() => _services.api
                      .putListItem(detail.id, detail.items[i].productId,
                          quantity: detail.items[i].quantity,
                          checked: checked)),
                  onQuantity: (q) => _change(() => _services.api.putListItem(
                      detail.id, detail.items[i].productId,
                      quantity: q)),
                  onRemove: () => _change(() => _services.api
                      .removeListItem(detail.id, detail.items[i].productId)),
                  onOpen: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => ProductScreen(
                              services: _services,
                              productId: detail.items[i].productId))),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  onPressed: _busy ? null : _toCart,
                  icon: const Icon(Icons.add_shopping_cart),
                  label: Text(s.addListToCart),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.busy,
    required this.onChecked,
    required this.onQuantity,
    required this.onRemove,
    required this.onOpen,
  });

  final GroceryListItem item;
  final bool busy;
  final void Function(bool) onChecked;
  final void Function(int) onQuantity;
  final VoidCallback onRemove;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final s = GStr.of(context);
    final theme = Theme.of(context);
    final step = item.unit == 'KG' ? 100 : 1;
    final max = item.unit == 'KG' ? 5000 : 20;
    return ListTile(
      onTap: onOpen,
      leading: Checkbox(
        value: item.checked,
        onChanged: busy ? null : (v) => onChecked(v ?? false),
      ),
      title: Text(item.name,
          style: TextStyle(
              fontWeight: FontWeight.w700,
              decoration: item.checked ? TextDecoration.lineThrough : null)),
      subtitle: Text(
        item.inStock
            ? '${formatQuantity(item.unit, item.quantity)} · ${unitPriceLabel(item.unit, item.priceMinor)}'
            : '${s.outOfStock} · ${item.storeName}',
        style: item.inStock ? null : TextStyle(color: theme.colorScheme.error),
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: '−',
          onPressed: busy || item.quantity <= step
              ? null
              : () => onQuantity(item.quantity - step),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        IconButton(
          tooltip: '+',
          onPressed: busy || item.quantity >= max
              ? null
              : () => onQuantity(item.quantity + step),
          icon: const Icon(Icons.add_circle_outline),
        ),
        IconButton(
          tooltip: s.delete,
          onPressed: busy ? null : onRemove,
          icon: const Icon(Icons.delete_outline),
        ),
      ]),
    );
  }
}

/// Favorite products of the customer (server-stored), with the same add-to-cart control as the catalog.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({required this.services, super.key});

  final GroceriesServices services;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  late Future<List<GroceryProduct>> _future = _load();

  GroceriesServices get _services => widget.services;

  /// The server list is the truth: its ids seed the shared favorites so that hearts and this list agree.
  Future<List<GroceryProduct>> _load() async {
    final list = await _services.api.favorites();
    _services.favorites.value = {
      ..._services.favorites.value,
      ...list.map((p) => p.id),
    };
    return list;
  }

  void _reload() => setState(() {
        _future = _load();
      });

  @override
  Widget build(BuildContext context) {
    final s = GStr.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.favorites)),
      bottomNavigationBar: FoodCartBar(services: _services.food),
      body: FutureBuilder<List<GroceryProduct>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SingleChildScrollView(
                child: ProductListSkeleton(rows: 4));
          }
          if (snapshot.hasError) {
            return GroceryMessage(
              icon: Icons.cloud_off_outlined,
              title: _error(snapshot.error!, s),
              actionLabel: s.retry,
              onAction: _reload,
            );
          }
          return ValueListenableBuilder<Set<String>>(
            valueListenable: _services.favorites,
            builder: (context, ids, _) {
              // Hearts removed here disappear from the list straight away; the server was already updated.
              final items =
                  snapshot.data!.where((p) => ids.contains(p.id)).toList();
              if (items.isEmpty) {
                return GroceryMessage(
                    icon: Icons.favorite_border,
                    title: s.emptyFavorites,
                    body: s.emptyFavoritesHint);
              }
              return ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) => ProductRow(
                  product: items[i],
                  services: _services,
                  onOpen: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => ProductScreen(
                              services: _services, productId: items[i].id))),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Bottom sheet to add [product] to one of the customer's lists, or to a new list.
Future<void> showAddToListSheet(
    BuildContext context, GroceriesServices services, GroceryProduct product) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _AddToListSheet(services: services, product: product),
  );
}

class _AddToListSheet extends StatefulWidget {
  const _AddToListSheet({required this.services, required this.product});

  final GroceriesServices services;
  final GroceryProduct product;

  @override
  State<_AddToListSheet> createState() => _AddToListSheetState();
}

class _AddToListSheetState extends State<_AddToListSheet> {
  late final Future<List<GroceryListSummary>> _future =
      widget.services.api.lists();

  Future<void> _add(String listId) async {
    final s = GStr.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await widget.services.api.putListItem(listId, widget.product.id,
          quantity: widget.product.defaultQuantity);
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(s.added)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(_error(error, s))));
    }
  }

  Future<void> _createAndAdd() async {
    final s = GStr.of(context);
    final name = await _askName(context, s.newList, '');
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final created = await widget.services.api.createList(name);
      await _add(created.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_error(error, s))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = GStr.of(context);
    return FutureBuilder<List<GroceryListSummary>>(
      future: _future,
      builder: (context, snapshot) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(s.newList),
            onTap: _createAndAdd,
          ),
          if (snapshot.connectionState != ConnectionState.done)
            const Padding(
                padding: EdgeInsets.all(16), child: CircularProgressIndicator())
          else if (snapshot.hasError)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error(snapshot.error!, s)),
            )
          else
            for (final list in snapshot.data!)
              ListTile(
                leading: const Icon(Icons.checklist_rtl),
                title: Text(list.name),
                subtitle: Text(s.listItems(list.items, list.checked)),
                onTap: () => _add(list.id),
              ),
        ]),
      ),
    );
  }
}
