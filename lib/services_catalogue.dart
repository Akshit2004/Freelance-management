import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models.dart';
import 'motion.dart';
import 'ui.dart';

class ServiceCataloguePage extends StatefulWidget {
  final bool pickMode;
  const ServiceCataloguePage({super.key, this.pickMode = false});

  @override
  State<ServiceCataloguePage> createState() => _ServiceCataloguePageState();
}

class _ServiceCataloguePageState extends State<ServiceCataloguePage> {
  final _search = TextEditingController();
  String _activeCategory = 'All';

  static const categories = ['All', 'Development', 'Design', 'Maintenance', 'API', 'Consulting', 'Other'];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openEditor([ServiceItem? item]) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _ServiceEditorSheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    final q = _search.text.trim().toLowerCase();
    final services = s.services.where((item) {
      final matchCat = _activeCategory == 'All' || item.category == _activeCategory;
      if (!matchCat) return false;
      if (q.isEmpty) return true;
      final hay = '${item.name} ${item.description} ${item.category} ${item.unit} ${money(item.rate)}'.toLowerCase();
      return q.split(RegExp(r'\s+')).every(hay.contains);
    }).toList();

    var i = 0;

    return Screen(
      title: widget.pickMode ? 'Select Service' : 'Service Catalogue',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Semantics(
            button: true,
            label: 'Add service',
            child: Pressable(
              onTap: () => _openEditor(),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.add_rounded, color: C.textLight, size: 22),
              ),
            ),
          ),
        ),
      ],
      body: RefreshListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
        children: [
          // Subtitle
          Text(
            'Save reusable services and standard rates for quick quoting and invoicing.',
            style: const TextStyle(fontSize: 13, color: C.muted, height: 1.4),
          ).enter(i++),
          const SizedBox(height: 14),

          // Search Box
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontFamily: 'Grotesk', fontSize: 14.5, color: C.text),
            decoration: InputDecoration(
              hintText: 'Search services, rates or categories',
              hintStyle: const TextStyle(color: C.dim, fontSize: 13.5),
              prefixIcon: const Icon(Icons.search_rounded, color: C.muted, size: 20),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: C.muted),
                      onPressed: () => setState(_search.clear),
                    ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              fillColor: C.card,
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.dark, width: 1.5)),
            ),
          ).enter(i++),
          const SizedBox(height: 12),

          // Category Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final cat in categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Pressable(
                      onTap: () => setState(() => _activeCategory = cat),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                        decoration: BoxDecoration(
                          color: _activeCategory == cat ? C.dark : C.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _activeCategory == cat ? C.dark : C.border),
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            fontFamily: 'Grotesk',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _activeCategory == cat ? C.textLight : C.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ).enter(i++),
          const SizedBox(height: 16),

          // List of Services
          if (services.isEmpty)
            EmptyState(
              Icons.inventory_2_outlined,
              q.isNotEmpty ? 'No matching services' : 'No services in $_activeCategory',
              q.isNotEmpty ? 'Try a different search query or add a new service.' : 'Tap + to add a service to your catalogue.',
            ).enter(i++)
          else
            for (final item in services)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ServiceCard(
                  item: item,
                  pickMode: widget.pickMode,
                  onEdit: () => _openEditor(item),
                  onPick: () => Navigator.pop(context, item),
                ).enter(i++),
              ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final ServiceItem item;
  final bool pickMode;
  final VoidCallback onEdit;
  final VoidCallback onPick;

  const _ServiceCard({
    required this.item,
    required this.pickMode,
    required this.onEdit,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return CardContainer(
      radius: 18,
      padding: const EdgeInsets.all(16),
      onTap: pickMode ? onPick : onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: display(16, weight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: C.chipLight, borderRadius: BorderRadius.circular(8)),
                      child: Text(item.category, style: mono(10, color: C.dim, weight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(money(item.rate), style: mono(16, weight: FontWeight.w700, color: C.text)),
                  const SizedBox(height: 2),
                  Text('per ${item.unit}', style: mono(11, color: C.muted)),
                ],
              ),
            ],
          ),
          if (item.description.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              item.description.trim(),
              style: const TextStyle(fontSize: 12.5, color: C.muted, height: 1.35),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (pickMode)
                Pressable(
                  onTap: onPick,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(10)),
                    child: const Text('Use in Document', style: TextStyle(fontFamily: 'Grotesk', fontSize: 12, fontWeight: FontWeight.w700, color: C.textLight)),
                  ),
                )
              else ...[
                Pressable(
                  onTap: () async {
                    final ok = await confirm(context, 'Delete service?', 'Remove "${item.name}" from your catalogue?');
                    if (ok && context.mounted) {
                      context.read<Store>().deleteService(item.id);
                      toast(context, 'Service deleted');
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text('Delete', style: TextStyle(fontSize: 12, color: C.red, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 8),
                Pressable(
                  onTap: onEdit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: C.cardDarkElevated, borderRadius: BorderRadius.circular(10)),
                    child: const Text('Edit', style: TextStyle(fontFamily: 'Grotesk', fontSize: 12, fontWeight: FontWeight.w700, color: C.textLight)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ServiceEditorSheet extends StatefulWidget {
  final ServiceItem? item;
  const _ServiceEditorSheet({this.item});

  @override
  State<_ServiceEditorSheet> createState() => _ServiceEditorSheetState();
}

class _ServiceEditorSheetState extends State<_ServiceEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _rate;
  late final TextEditingController _unit;
  late final TextEditingController _desc;
  late String _category;

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    _name = TextEditingController(text: it?.name ?? '');
    _rate = TextEditingController(text: it != null && it.rate > 0 ? it.rate.toString() : '');
    _unit = TextEditingController(text: it?.unit ?? 'hr');
    _desc = TextEditingController(text: it?.description ?? '');
    _category = it?.category ?? 'Development';
  }

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    _unit.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      toast(context, 'Please enter a service name');
      return;
    }
    final rate = double.tryParse(_rate.text.trim()) ?? 0;
    final unit = _unit.text.trim().isEmpty ? 'hr' : _unit.text.trim();
    final desc = _desc.text.trim();

    final item = widget.item?.copy() ?? ServiceItem();
    item.name = name;
    item.rate = rate;
    item.unit = unit;
    item.category = _category;
    item.description = desc;

    context.read<Store>().putService(item);
    Navigator.pop(context);
    toast(context, widget.item == null ? 'Service added' : 'Service updated');
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.item == null;
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, inset + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text(isNew ? 'New Service' : 'Edit Service', style: display(20))),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: isNew,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Service Name',
                hintText: 'e.g. Frontend Development, UI Design',
                filled: true,
                fillColor: C.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _rate,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Standard Rate (${store.profile.currency})',
                      hintText: '0',
                      filled: true,
                      fillColor: C.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _unit,
                    decoration: InputDecoration(
                      labelText: 'Unit',
                      hintText: 'hr / project / mo',
                      filled: true,
                      fillColor: C.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: InputDecoration(
                labelText: 'Category',
                filled: true,
                fillColor: C.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
              ),
              items: [
                for (final c in ['Development', 'Design', 'Maintenance', 'API', 'Consulting', 'Other'])
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => v != null ? setState(() => _category = v) : null,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Default Description (Optional)',
                hintText: 'Scope, deliverables or details that appear on invoices and quotes...',
                filled: true,
                fillColor: C.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
              ),
            ),
            const SizedBox(height: 20),
            Pressable(
              onTap: _save,
              child: Container(
                constraints: const BoxConstraints(minHeight: 50),
                decoration: BoxDecoration(color: C.dark, borderRadius: BorderRadius.circular(16)),
                alignment: Alignment.center,
                child: Text(isNew ? 'Add to Catalogue' : 'Save Changes',
                    style: const TextStyle(fontFamily: 'Grotesk', fontWeight: FontWeight.w700, fontSize: 15, color: C.textLight)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
