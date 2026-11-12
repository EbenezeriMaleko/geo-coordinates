import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../auth/providers/auth_provider.dart';
import '../../subscriptions/entitlement_provider.dart';
import '../../subscriptions/subscription_provider.dart';
import '../../subscriptions/plans_access_page.dart';
import '../../workspaces/workspace_provider.dart';
import '../../workspaces/workspace_page_style.dart';
import '../services/record_export_service.dart';

String? recordExportBlock(
  RecordExportFormat format,
  AsyncValue<Map<String, dynamic>> access,
) {
  if (format == RecordExportFormat.csv) return null;
  final data = access.asData?.value;
  if (data == null) {
    return access.isLoading
        ? 'Checking format access...'
        : 'Format access is unavailable. Refresh access.';
  }
  final features = (data['features'] as List? ?? []).whereType<Map>();
  final decision = features
      .where((item) => item['key'] == 'land.export')
      .firstOrNull;
  if (decision?['allowed'] != true) {
    return decision?['reason'] == 'company_role_forbidden'
        ? 'Your company role does not allow this format.'
        : 'Not available with your current workspace access.';
  }
  final limits = data['transfer_limits'];
  final formats = limits is Map ? limits['export_formats'] : null;
  if (formats is! List) return 'Format access is unavailable. Refresh access.';
  return formats.contains(format.extension)
      ? null
      : 'Not included in this workspace plan.';
}

class RecordExportPage extends ConsumerStatefulWidget {
  const RecordExportPage({
    super.key,
    required this.company,
    required this.record,
    required this.name,
  });
  final int? company;
  final String record;
  final String name;
  @override
  ConsumerState<RecordExportPage> createState() => _RecordExportPageState();
}

class _RecordExportPageState extends ConsumerState<RecordExportPage> {
  late final token = ref.read(authSessionProvider).token;
  RecordExportFormat format = RecordExportFormat.csv;
  RecordExportFile? file;
  bool busy = false;
  String? error;
  String? message;
  bool get current =>
      mounted &&
      token == ref.read(authSessionProvider).token &&
      ref.read(authSessionProvider).isLoggedIn &&
      ref.read(authSessionProvider).isVerified &&
      widget.company == ref.read(workspaceProvider).activeCompanyId;

  Future<void> export(BuildContext buttonContext) async {
    if (busy ||
        !current ||
        ref.read(workspaceProvider).isLoading ||
        recordExportBlock(format, ref.read(workspaceAccessSnapshotProvider)) !=
            null) {
      return;
    }
    final service = ref.read(recordExportServiceProvider);
    if (service.pending(widget.record)) {
      setState(
        () => error =
            'Sync or resolve pending local edits before exporting the saved cloud record.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      if (file == null) {
        final downloaded = await service.download(
          token,
          widget.record,
          format,
          isCurrent: () => current,
        );
        if (!mounted || !current) return;
        file = downloaded;
        ref.invalidate(subscriptionOverviewProvider);
      }
      if (!mounted || !current || !buttonContext.mounted) return;
      if (service.pending(widget.record)) {
        setState(() {
          file = null;
          error = 'Newer local edits need syncing before file export.';
        });
        return;
      }
      final box = buttonContext.findRenderObject();
      final origin = box is RenderBox && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : const Rect.fromLTWH(0, 0, 1, 1);
      final status = await service.share(file!, origin);
      if (!mounted || !current) return;
      setState(
        () => message = status == ShareResultStatus.success
            ? 'File shared.'
            : status == ShareResultStatus.dismissed
            ? 'Sharing cancelled. File is ready.'
            : 'File is ready.',
      );
    } catch (failure) {
      if (current) {
        setState(
          () => error = file == null
              ? failure.toString().replaceFirst('Exception: ', '')
              : 'File is ready, but sharing could not be opened. Try sharing again.',
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
    final access = ref.watch(workspaceAccessSnapshotProvider);
    final block = recordExportBlock(format, access);
    return PopScope(
      canPop: !busy,
      child: WorkspaceScaffold(
        company: widget.company != null,
        appBar: AppBar(
          title: const Text('Export record'),
          actions: [
            IconButton(
              tooltip: 'Refresh export access',
              onPressed: available && !busy
                  ? () => ref.invalidate(workspaceAccessSnapshotProvider)
                  : null,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: !available
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Workspace or account changed. Reopen export.'),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    widget.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    workspace.label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  RadioGroup<RecordExportFormat>(
                    groupValue: format,
                    onChanged: (value) {
                      if (!busy && value != null) {
                        setState(() {
                          format = value;
                          file = null;
                          error = null;
                          message = null;
                        });
                      }
                    },
                    child: Column(
                      children: [
                        for (final option in RecordExportFormat.values)
                          RadioListTile<RecordExportFormat>(
                            contentPadding: EdgeInsets.zero,
                            value: option,
                            enabled:
                                !busy &&
                                recordExportBlock(option, access) == null,
                            title: Text(option.label),
                            subtitle: Text(
                              recordExportBlock(option, access) ??
                                  (option == RecordExportFormat.csv
                                      ? 'Individual CSV access remains available.'
                                      : 'Included in current export access.'),
                            ),
                            secondary: recordExportBlock(option, access) == null
                                ? null
                                : const Icon(Icons.lock_outline, size: 20),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Exports use the saved cloud record. Non-CSV downloads may count toward the monthly export allowance.',
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const PlansAccessPage(),
                            ),
                          ),
                    child: const Text('Plans & Access'),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(message!),
                    ),
                  if (file != null)
                    Text(
                      file!.name,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 20),
                  Builder(
                    builder: (buttonContext) => FilledButton.icon(
                      onPressed: busy || block != null
                          ? null
                          : () => export(buttonContext),
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.ios_share, size: 18),
                      label: Text(
                        busy
                            ? 'Preparing...'
                            : file == null
                            ? 'Export file'
                            : 'Share file',
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
