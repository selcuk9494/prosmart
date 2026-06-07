import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api_client.dart';
import '../../app/config.dart';
import '../../domain/stores.dart';
import '../../legacy/crm_menu.dart';

class AdminUserMenuPermissionsPage extends ConsumerStatefulWidget {
  const AdminUserMenuPermissionsPage({super.key});

  @override
  ConsumerState<AdminUserMenuPermissionsPage> createState() =>
      _AdminUserMenuPermissionsPageState();
}

class _AdminUserMenuPermissionsPageState
    extends ConsumerState<AdminUserMenuPermissionsPage> {
  String? _selectedUserId;
  var _busy = false;
  final Set<String> _selectedRefs = {};

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(usersProvider);
    final crmMenu = ref.watch(crmMenuProvider);
    final menuSections = crmMenu.asData?.value;
    final canToggleAll = !_busy && _selectedUserId != null && menuSections != null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Kullanıcı Menü Yetkilendirme',
                style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            SizedBox(
              width: 160,
              child: OutlinedButton(
                onPressed: canToggleAll ? () => _selectAll(menuSections!) : null,
                child: const Text('Tümünü Aç'),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 160,
              child: OutlinedButton(
                onPressed: _busy || _selectedUserId == null ? null : _clearAll,
                child: const Text('Tümünü Kapat'),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 140,
              child: FilledButton(
                onPressed: _busy || _selectedUserId == null ? null : _save,
                child: const Text('Kaydet'),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 140,
              child: OutlinedButton(
                onPressed: _busy ? null : () => context.go('/'),
                child: const Text('Kapat'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: _selectedUserId,
                  decoration: const InputDecoration(labelText: 'Kullanıcı'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Seçiniz')),
                    for (final u in users)
                      DropdownMenuItem(
                        value: u.id,
                        child: Text('${u.username} • ${u.displayName}'),
                      ),
                  ],
                  onChanged: (v) async {
                    setState(() {
                      _selectedUserId = v;
                      _selectedRefs.clear();
                    });
                    if (v != null) {
                      await _loadForUser(v);
                    }
                  },
                ),
                const SizedBox(height: 12),
                crmMenu.when(
                  data: (sections) {
                    if (_selectedUserId == null) {
                      return const Text('Önce kullanıcı seçiniz.');
                    }

                    return Column(
                      children: [
                        for (final s in sections)
                          _PermissionSection(
                            title: s.title,
                            nodes: s.nodes,
                            selectedRefs: _selectedRefs,
                            onToggleRef: _toggleRef,
                            onToggleNode: _toggleNode,
                          ),
                      ],
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, st) => const Text('Menü okunamadı.'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _loadForUser(String userId) async {
    setState(() => _busy = true);
    try {
      if (!AppConfig.hasApi) {
        _selectedRefs.addAll(const ['insert_firma', 'insert_depo', 'insert_recete']);
        return;
      }

      final dio = ref.read(dioProvider);
      final res = await dio.get<List<dynamic>>(
        '/user-menu-permissions',
        queryParameters: {'userId': userId},
      );
      final data = res.data ?? const [];
      _selectedRefs
        ..clear()
        ..addAll([for (final x in data) x.toString()]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yetkiler okunamadı.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final userId = _selectedUserId;
    if (userId == null) return;

    setState(() => _busy = true);
    try {
      if (AppConfig.hasApi) {
        final dio = ref.read(dioProvider);
        await dio.put<Map<String, dynamic>>(
          '/user-menu-permissions/$userId',
          data: {'legacyRefs': _selectedRefs.toList()..sort()},
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kaydedildi.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kaydetme başarısız.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleRef(String legacyRef, bool on) {
    setState(() {
      if (on) {
        _selectedRefs.add(legacyRef);
      } else {
        _selectedRefs.remove(legacyRef);
      }
    });
  }

  void _toggleNode(CrmMenuNode node, bool on) {
    final refs = _collectLeafRefs(node);
    setState(() {
      if (on) {
        _selectedRefs.addAll(refs);
      } else {
        _selectedRefs.removeAll(refs);
      }
    });
  }

  void _selectAll(List<CrmMenuSection> sections) {
    final refs = <String>{};
    for (final s in sections) {
      for (final n in s.nodes) {
        refs.addAll(_collectLeafRefs(n));
      }
    }
    setState(() {
      _selectedRefs
        ..clear()
        ..addAll(refs);
    });
  }

  void _clearAll() {
    setState(() {
      _selectedRefs.clear();
    });
  }

  List<String> _collectLeafRefs(CrmMenuNode node) {
    if (node.children == null || node.children!.isEmpty) {
      final ref = node.legacyRef ?? node.subtitle ?? '';
      return ref.isEmpty ? const [] : [ref];
    }
    final out = <String>[];
    for (final c in node.children!) {
      out.addAll(_collectLeafRefs(c));
    }
    return out;
  }
}

class _PermissionSection extends StatelessWidget {
  const _PermissionSection({
    required this.title,
    required this.nodes,
    required this.selectedRefs,
    required this.onToggleRef,
    required this.onToggleNode,
  });

  final String title;
  final List<CrmMenuNode> nodes;
  final Set<String> selectedRefs;
  final void Function(String legacyRef, bool on) onToggleRef;
  final void Function(CrmMenuNode node, bool on) onToggleNode;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(title),
      children: [
        for (final n in nodes)
          _PermissionNode(
            node: n,
            selectedRefs: selectedRefs,
            onToggleRef: onToggleRef,
            onToggleNode: onToggleNode,
          ),
      ],
    );
  }
}

class _PermissionNode extends StatelessWidget {
  const _PermissionNode({
    required this.node,
    required this.selectedRefs,
    required this.onToggleRef,
    required this.onToggleNode,
  });

  final CrmMenuNode node;
  final Set<String> selectedRefs;
  final void Function(String legacyRef, bool on) onToggleRef;
  final void Function(CrmMenuNode node, bool on) onToggleNode;

  @override
  Widget build(BuildContext context) {
    final children = node.children ?? const [];
    if (children.isEmpty) {
      final ref = node.legacyRef ?? node.subtitle ?? '';
      if (ref.isEmpty) return const SizedBox.shrink();
      final checked = selectedRefs.contains(ref);
      return CheckboxListTile(
        dense: true,
        value: checked,
        onChanged: (v) => onToggleRef(ref, v ?? false),
        title: Text(node.title),
        subtitle: node.subtitle == null ? null : Text(node.subtitle!),
      );
    }

    final leafRefs = _collectLeafRefs(node);
    final selectedCount = leafRefs.where(selectedRefs.contains).length;
    final allSelected = selectedCount == leafRefs.length && leafRefs.isNotEmpty;
    final noneSelected = selectedCount == 0;
    final tristateValue = noneSelected ? false : (allSelected ? true : null);

    return ExpansionTile(
      title: Row(
        children: [
          Checkbox(
            tristate: true,
            value: tristateValue,
            onChanged: (v) => onToggleNode(node, v == true),
          ),
          Expanded(child: Text(node.title)),
        ],
      ),
      children: [
        for (final c in children)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: _PermissionNode(
              node: c,
              selectedRefs: selectedRefs,
              onToggleRef: onToggleRef,
              onToggleNode: onToggleNode,
            ),
          ),
      ],
    );
  }

  List<String> _collectLeafRefs(CrmMenuNode node) {
    final children = node.children ?? const [];
    if (children.isEmpty) {
      final ref = node.legacyRef ?? node.subtitle ?? '';
      return ref.isEmpty ? const [] : [ref];
    }
    final out = <String>[];
    for (final c in children) {
      out.addAll(_collectLeafRefs(c));
    }
    return out;
  }
}
