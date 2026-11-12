import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../../subscriptions/entitlement_provider.dart';
import '../../workspaces/workspace_provider.dart';
import '../../workspaces/workspace_page_style.dart';
import '../providers/land_cloud_provider.dart';
import '../services/record_recovery_service.dart';

String recoveryDate(BuildContext context, dynamic raw) {
  final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  return date == null
      ? 'Unavailable'
      : MaterialLocalizations.of(context).formatMediumDate(date);
}

bool recoveryWriteAccess(WidgetRef ref, int? company, {required bool trash}) {
  final features = ref.watch(entitlementProvider).asData?.value;
  final permissions = ref.watch(workspacePermissionsProvider).asData?.value;
  return (company == null || permissions?['records.write'] == true) &&
      features?['land.view_and_edit']?.allowed == true &&
      (!trash ||
          (features?['land.create_and_save']?.allowed == true &&
              features?['land.sync']?.allowed == true));
}

Future<bool?> confirmRecovery(BuildContext context, String message) =>
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore record?'),
        content: Text(message),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Restore'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );

class RecordRecoveryPage extends ConsumerStatefulWidget {
  const RecordRecoveryPage({
    super.key,
    required this.company,
    this.record,
    this.canManage = true,
    this.onRestored,
  });
  final int? company;
  final String? record;
  final bool canManage;
  final Future<void> Function()? onRestored;
  @override
  ConsumerState<RecordRecoveryPage> createState() => _RecordRecoveryPageState();
}

class _RecordRecoveryPageState extends ConsumerState<RecordRecoveryPage> {
  late final token = ref.read(authSessionProvider).token;
  int page = 1;
  String search = '';
  bool busy = false;
  bool confirming = false;
  String? error;
  bool get current =>
      mounted &&
      token == ref.read(authSessionProvider).token &&
      ref.read(authSessionProvider).isVerified &&
      widget.company == ref.read(workspaceProvider).activeCompanyId;

  Future<void> restore(Map record) async {
    if (busy || confirming || !current || record['can_restore'] != true) return;
    final id = record['id'].toString();
    final service = ref.read(recordRecoveryServiceProvider);
    if (service.pending(id)) {
      setState(
        () => error =
            'Sync or resolve pending local edits for this record before restoring it.',
      );
      return;
    }
    confirming = true;
    bool? confirmed;
    try {
      confirmed = await confirmRecovery(
        context,
        '${record['name'] ?? 'This record'} will return to the Library if your current record and point allowances permit.',
      );
    } finally {
      confirming = false;
    }
    if (!current || confirmed != true) return;
    if (service.pending(id)) {
      setState(
        () =>
            error = 'Pending local edits must be resolved before restoration.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await service.restore(token, id);
      if (!mounted || !current) return;
      var warning = false;
      try {
        await service.refreshCache(token, widget.company, id);
      } catch (_) {
        warning = true;
      }
      if (!mounted || !current) return;
      ref.invalidate(recoveryListProvider);
      ref.invalidate(remoteLandDetailProvider(id));
      try {
        await widget.onRestored?.call();
      } catch (_) {
        warning = true;
      }
      if (!mounted || !current) return;
      setState(() => page = 1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            warning
                ? 'Record restored. Refresh the Library before further edits; cached details could not refresh.'
                : 'Record restored.',
          ),
        ),
      );
    } catch (failure) {
      if (current) {
        setState(
          () => error = failure.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    ref.watch(authSessionProvider);
    final available = current && !workspace.isLoading;
    final history = widget.record != null;
    final query = (
      company: widget.company,
      record: widget.record,
      search: search,
      page: page,
    );
    final result = available ? ref.watch(recoveryListProvider(query)) : null;
    final writable = recoveryWriteAccess(ref, widget.company, trash: !history);
    Future<void> refresh() async {
      ref.invalidate(recoveryListProvider(query));
      try {
        await ref.read(recoveryListProvider(query).future);
      } catch (_) {}
    }

    return PopScope(
      canPop: !busy,
      child: WorkspaceScaffold(
        company: widget.company != null,
        appBar: AppBar(
          title: Text(history ? 'Record history' : 'Recycle bin'),
          actions: [
            IconButton(
              tooltip: 'Refresh recovery',
              onPressed: available && !busy ? refresh : null,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: !available
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Workspace or account changed. Reopen this page.',
                  ),
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        workspace.label,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ),
                  if (!history)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: TextField(
                        enabled: !busy,
                        maxLength: 255,
                        decoration: const InputDecoration(
                          hintText: 'Search deleted records',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onSubmitted: (value) => setState(() {
                          search = value.trim();
                          page = 1;
                        }),
                        textInputAction: TextInputAction.search,
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Expanded(
                    child: result!.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, _) => Center(
                        child: TextButton.icon(
                          onPressed: refresh,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Unable to load records. Retry'),
                        ),
                      ),
                      data: (data) {
                        final items = (data['data'] as List? ?? [])
                            .whereType<Map>()
                            .toList();
                        final meta = data['meta'] is Map
                            ? data['meta'] as Map
                            : const {};
                        final last = (meta['last_page'] as num?)?.toInt() ?? 1;
                        final policy = data['policy'] is Map
                            ? data['policy'] as Map
                            : const {};
                        return Column(
                          children: [
                            if (history && policy['enabled'] != true)
                              const Padding(
                                padding: EdgeInsets.all(20),
                                child: Text(
                                  'History is not available under the current workspace plan.',
                                ),
                              ),
                            Expanded(
                              child: RefreshIndicator(
                                onRefresh: refresh,
                                child: ListView.separated(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  itemCount: items.isEmpty ? 1 : items.length,
                                  separatorBuilder: (_, _) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    if (items.isEmpty) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 32,
                                        ),
                                        child: Text(
                                          history
                                              ? 'No retained versions available.'
                                              : 'No deleted records found.',
                                        ),
                                      );
                                    }
                                    final item = items[index];
                                    if (history) {
                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: const Icon(Icons.history),
                                        title: Text(
                                          item['record_name']?.toString() ??
                                              'Saved version',
                                        ),
                                        subtitle: Text(
                                          '${recoveryDate(context, item['created_at'])}\n${item['actor'] is Map ? item['actor']['name'] ?? 'Unavailable account' : 'Unavailable account'} - ${item['point_count'] ?? 0} points',
                                        ),
                                        trailing: const Icon(
                                          Icons.chevron_right,
                                        ),
                                        onTap: busy
                                            ? null
                                            : () {
                                                final version = int.tryParse(
                                                  item['id'].toString(),
                                                );
                                                if (version == null) return;
                                                Navigator.of(context).push(
                                                  MaterialPageRoute<void>(
                                                    builder: (_) => RecordVersionPage(
                                                      company: widget.company,
                                                      record: widget.record!,
                                                      version: version,
                                                      revision:
                                                          data['current_revision']
                                                              ?.toString(),
                                                      canRestore:
                                                          widget.canManage &&
                                                          data['can_restore'] ==
                                                              true,
                                                      onRestored:
                                                          widget.onRestored,
                                                    ),
                                                  ),
                                                );
                                              },
                                      );
                                    }
                                    final reason = switch (item['reason']) {
                                      'workspace_read_only' =>
                                        'Workspace is read-only',
                                      'not_included' =>
                                        'Restoration was not included when deleted',
                                      'restore_period_ended' =>
                                        'Restore period ended; not permanently deleted',
                                      _ => null,
                                    };
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['name']?.toString() ??
                                                'Deleted record',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleSmall,
                                          ),
                                          Text(
                                            'Deleted ${recoveryDate(context, item['deleted_at'])}',
                                          ),
                                          if (item['restore_until'] != null)
                                            Text(
                                              'Restore until ${recoveryDate(context, item['restore_until'])}',
                                            ),
                                          if (reason != null) Text(reason),
                                          if (item['can_restore'] == true &&
                                              writable)
                                            TextButton.icon(
                                              onPressed: busy
                                                  ? null
                                                  : () => restore(item),
                                              icon: const Icon(
                                                Icons.restore,
                                                size: 18,
                                              ),
                                              label: const Text(
                                                'Restore record',
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  tooltip: 'Previous recovery page',
                                  onPressed: !busy && page > 1
                                      ? () => setState(() => page--)
                                      : null,
                                  icon: const Icon(Icons.chevron_left),
                                ),
                                Flexible(child: Text('Page $page of $last')),
                                IconButton(
                                  tooltip: 'Next recovery page',
                                  onPressed: !busy && page < last
                                      ? () => setState(() => page++)
                                      : null,
                                  icon: const Icon(Icons.chevron_right),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class RecordVersionPage extends ConsumerStatefulWidget {
  const RecordVersionPage({
    super.key,
    required this.company,
    required this.record,
    required this.version,
    required this.revision,
    required this.canRestore,
    this.onRestored,
  });
  final int? company;
  final String record;
  final int version;
  final String? revision;
  final bool canRestore;
  final Future<void> Function()? onRestored;
  @override
  ConsumerState<RecordVersionPage> createState() => _RecordVersionPageState();
}

class _RecordVersionPageState extends ConsumerState<RecordVersionPage> {
  late final token = ref.read(authSessionProvider).token;
  bool busy = false;
  bool confirming = false;
  String? error;
  int pointsPage = 1;
  bool get current =>
      mounted &&
      token == ref.read(authSessionProvider).token &&
      ref.read(authSessionProvider).isVerified &&
      widget.company == ref.read(workspaceProvider).activeCompanyId;
  Future<void> restore() async {
    if (!current ||
        busy ||
        confirming ||
        !widget.canRestore ||
        widget.revision == null) {
      return;
    }
    final service = ref.read(recordRecoveryServiceProvider);
    if (service.pending(widget.record)) {
      setState(
        () => error =
            'Sync or resolve pending local edits before restoring a version.',
      );
      return;
    }
    confirming = true;
    bool? confirmed;
    try {
      confirmed = await confirmRecovery(
        context,
        'The saved details and geometry will replace the current record. The current version is preserved in history first. Media and markers stay unchanged.',
      );
    } finally {
      confirming = false;
    }
    if (!current || confirmed != true) return;
    if (service.pending(widget.record)) {
      setState(() => error = 'Pending local edits must be resolved first.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await service.restore(
        token,
        widget.record,
        version: widget.version,
        revision: widget.revision,
      );
      if (!mounted || !current) return;
      var warning = false;
      try {
        await service.refreshCache(token, widget.company, widget.record);
      } catch (_) {
        warning = true;
      }
      if (!mounted || !current) return;
      ref.invalidate(recoveryListProvider);
      ref.invalidate(remoteLandDetailProvider(widget.record));
      try {
        await widget.onRestored?.call();
      } catch (_) {
        warning = true;
      }
      if (!mounted || !current) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            warning
                ? 'Version restored. Refresh the Library before further edits; cached details could not refresh.'
                : 'Record version restored.',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (failure) {
      if (current) {
        setState(
          () => error = failure.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authSessionProvider);
    final workspace = ref.watch(workspaceProvider);
    final available = current && !workspace.isLoading;
    final query = (
      company: widget.company,
      record: widget.record,
      version: widget.version,
    );
    final result = available ? ref.watch(recoveryVersionProvider(query)) : null;
    final writable = recoveryWriteAccess(ref, widget.company, trash: false);
    return PopScope(
      canPop: !busy,
      child: WorkspaceScaffold(
        company: widget.company != null,
        appBar: AppBar(title: const Text('Saved version')),
        body: !available
            ? const Center(
                child: Text('Workspace or account changed. Reopen history.'),
              )
            : result!.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: TextButton(
                    onPressed: () =>
                        ref.invalidate(recoveryVersionProvider(query)),
                    child: const Text('Unable to load version. Retry'),
                  ),
                ),
                data: (data) {
                  final snapshot = data['snapshot'] is Map
                      ? data['snapshot'] as Map
                      : const {};
                  final attributes = snapshot['attributes'] is Map
                      ? snapshot['attributes'] as Map
                      : const {};
                  final points = (snapshot['points'] as List? ?? [])
                      .whereType<Map>()
                      .toList();
                  final last = ((points.length + 19) ~/ 20).clamp(1, 1000000);
                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        attributes['name']?.toString() ?? 'Saved record',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Saved ${recoveryDate(context, data['created_at'])}',
                      ),
                      const Divider(height: 32),
                      for (final entry in const {
                        'type': 'Geometry',
                        'place': 'Place',
                        'phone': 'Phone',
                        'description': 'Description',
                        'reference_ellipsoid': 'Reference ellipsoid',
                        'area': 'Area (m2)',
                        'perimeter': 'Perimeter (m)',
                      }.entries)
                        if (attributes[entry.key] != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              '${entry.value}: ${attributes[entry.key]}',
                            ),
                          ),
                      const SizedBox(height: 20),
                      Text(
                        '${points.length} saved points',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Point')),
                            DataColumn(label: Text('Latitude (y)')),
                            DataColumn(label: Text('Longitude (x)')),
                          ],
                          rows: [
                            for (final point
                                in points.skip((pointsPage - 1) * 20).take(20))
                              DataRow(
                                cells: [
                                  DataCell(
                                    Text(
                                      '${point['label'] ?? point['point_order'] ?? ''}',
                                    ),
                                  ),
                                  DataCell(Text('${point['y'] ?? ''}')),
                                  DataCell(Text('${point['x'] ?? ''}')),
                                ],
                              ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: 'Previous points page',
                            onPressed: pointsPage > 1
                                ? () => setState(() => pointsPage--)
                                : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Flexible(child: Text('Page $pointsPage of $last')),
                          IconButton(
                            tooltip: 'Next points page',
                            onPressed: pointsPage < last
                                ? () => setState(() => pointsPage++)
                                : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (error != null)
                        TextButton.icon(
                          onPressed: busy
                              ? null
                              : () {
                                  ref.invalidate(recoveryListProvider);
                                  Navigator.pop(context);
                                },
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Reload history'),
                        ),
                      if (widget.canRestore &&
                          writable &&
                          RegExp(
                            r'^[a-f0-9]{64}$',
                          ).hasMatch(widget.revision ?? ''))
                        FilledButton.icon(
                          onPressed: busy ? null : restore,
                          icon: const Icon(Icons.restore, size: 18),
                          label: Text(
                            busy ? 'Restoring...' : 'Restore version',
                          ),
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
