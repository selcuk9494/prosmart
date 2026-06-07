import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../domain/models.dart';
import '../../domain/stores.dart';

class DocumentUploadPage extends ConsumerWidget {
  const DocumentUploadPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branches = ref.watch(branchesProvider);
    final items = ref.watch(reconciliationsProvider);
    final missingDocs = [
      for (final r in items)
        if (missingRequiredAttachmentKinds(r).isNotEmpty) r,
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Evrak', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            Text('${missingDocs.length} eksik'),
          ],
        ),
        const SizedBox(height: 12),
        if (missingDocs.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Eksik evrak yok.'),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final r in missingDocs)
                  ListTile(
                    onTap: () => context.go('/reconciliations/${r.id}'),
                    title: Text(
                      '${_branchName(branches, r.branchId)} • ${DateFormat('yyyy-MM-dd', 'tr_TR').format(r.date)}',
                    ),
                    subtitle: Text(
                      'Eksik: ${missingRequiredAttachmentKinds(r).map(attachmentKindLabel).join(', ')}',
                    ),
                    trailing: FilledButton(
                      onPressed: () => context.go('/reconciliations/${r.id}'),
                      child: const Text('Yükle'),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _branchName(List<Branch> branches, String id) {
    return branches
        .firstWhere((b) => b.id == id, orElse: () => const Branch(id: 'x', name: '?'))
        .name;
  }
}

