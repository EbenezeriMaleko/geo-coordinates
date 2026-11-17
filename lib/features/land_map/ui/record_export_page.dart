import '../../widget/plan_access_lock.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../widget/library_record_style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../auth/providers/auth_provider.dart';
import '../../subscriptions/entitlement_provider.dart';
import '../../subscriptions/subscription_provider.dart';
import '../../subscriptions/plans_access_page.dart';
import '../../workspaces/workspace_provider.dart';
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
      child: LibraryRecordScaffold(
        company: widget.company != null,
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedArrowLeft01,
              size: 22,
            ),
          ),
          centerTitle: true,
          title: const Text('Export record'),
          actions: [
            IconButton(
              tooltip: 'Refresh export access',
              onPressed: available && !busy
                  ? () => ref.invalidate(workspaceAccessSnapshotProvider)
                  : null,
              icon: const HugeIcon(
                size: 20,
                icon: HugeIcons.strokeRoundedRefresh,
              ),
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
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LibraryRecordHeader(
                      icon: HugeIcons.strokeRoundedFileExport,
                      title: widget.name,
                      subtitle: workspace.label,
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(8, 0, 8, 12),
                      child: Text(
                        'CHOOSE FILE FORMAT',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: Colors.black45,
                        ),
                      ),
                    ),
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
                            PlanAccessLock(
                              locked:
                                  access.asData != null &&
                                  recordExportBlock(option, access) != null,
                              child: _ExportFormatOption(
                                option: option,
                                selected: format == option,
                                enabled:
                                    !busy &&
                                    recordExportBlock(option, access) == null,
                                block: recordExportBlock(option, access),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE8ECF0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              HugeIcon(
                                icon: HugeIcons.strokeRoundedInformationCircle,
                                size: 18,
                                color: Color(0xFF001F3F),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'About this export',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Exports use the saved cloud record. Non-CSV downloads may count toward the monthly export allowance.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextButton.icon(
                            onPressed: busy
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const PlansAccessPage(),
                                    ),
                                  ),
                            icon: const HugeIcon(
                              icon: HugeIcons.strokeRoundedArrowRight01,
                              size: 16,
                            ),
                            label: const Text('Plans & Access'),
                          ),
                        ],
                      ),
                    ),
                    if (error != null)
                      _ExportNotice(text: error!, isError: true),
                    if (message != null) _ExportNotice(text: message!),
                    if (file != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE8ECF0)),
                          ),
                          child: Row(
                            children: [
                              const HugeIcon(
                                icon: HugeIcons.strokeRoundedFileExport,
                                size: 20,
                                color: Color(0xFF001F3F),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'File ready',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      file!.name,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    Builder(
                      builder: (buttonContext) => PlanAccessLock(
                        locked: access.asData != null && block != null && !busy,
                        child: FilledButton.icon(
                          onPressed: busy || block != null
                              ? null
                              : () => export(buttonContext),
                          icon: busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const HugeIcon(
                                  icon: HugeIcons.strokeRoundedShare01,
                                  size: 18,
                                ),
                          label: Text(
                            busy
                                ? 'Preparing...'
                                : file == null
                                ? 'Export file'
                                : 'Share file',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ExportFormatOption extends StatelessWidget {
  const _ExportFormatOption({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.block,
  });
  final RecordExportFormat option;
  final bool selected;
  final bool enabled;
  final String? block;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? Color.alphaBlend(accent.withValues(alpha: .06), Colors.white)
            : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? accent : const Color(0xFFE8ECF0),
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: RadioListTile<RecordExportFormat>(
          value: option,
          enabled: enabled,
          selected: selected,
          shape: const RoundedRectangleBorder(),
          tileColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          title: Text(
            option.label,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              block ??
                  switch (option) {
                    RecordExportFormat.csv =>
                      'Coordinates in a spreadsheet-friendly table.',
                    RecordExportFormat.kml =>
                      'Geometry for compatible map and GIS tools.',
                    RecordExportFormat.geojson =>
                      'Geometry for GIS and mapping applications.',
                  },
              style: const TextStyle(
                fontSize: 12.5,
                color: Colors.black54,
                height: 1.4,
              ),
            ),
          ),
          secondary: block != null
              ? const HugeIcon(
                  icon: HugeIcons.strokeRoundedLockKey,
                  size: 20,
                  color: Colors.black38,
                )
              : Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: HugeIcon(
                    icon: switch (option) {
                      RecordExportFormat.csv =>
                        HugeIcons.strokeRoundedFileExport,
                      RecordExportFormat.kml => HugeIcons.strokeRoundedGlobe02,
                      RecordExportFormat.geojson => HugeIcons.strokeRoundedMaps,
                    },
                    size: 20,
                    color: accent,
                  ),
                ),
        ),
      ),
    );
  }
}

class _ExportNotice extends StatelessWidget {
  const _ExportNotice({required this.text, this.isError = false});
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? const Color(0xFFB42318) : const Color(0xFF001F3F);
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HugeIcon(
            icon: isError
                ? HugeIcons.strokeRoundedAlertCircle
                : HugeIcons.strokeRoundedInformationCircle,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, height: 1.4, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
