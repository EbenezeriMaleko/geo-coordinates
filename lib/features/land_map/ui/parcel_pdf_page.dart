import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../widget/library_record_style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../auth/providers/auth_provider.dart';
import '../../workspaces/workspace_provider.dart';
import '../services/parcel_pdf_service.dart';

class ParcelPdfPage extends ConsumerStatefulWidget {
  const ParcelPdfPage({
    super.key,
    required this.company,
    required this.record,
    required this.name,
  });
  final int? company;
  final String record;
  final String name;
  @override
  ConsumerState<ParcelPdfPage> createState() => _ParcelPdfPageState();
}

class _ParcelPdfPageState extends ConsumerState<ParcelPdfPage> {
  late final token = ref.read(authSessionProvider).token;
  SavedParcelPdf? report;
  ParcelPdfFile? file;
  ParcelReportPolicy? policy;
  ParcelReportLogo? logo;
  String? logoName;
  String? policyError;
  bool loading = true;
  bool busy = false;
  String? error;
  String? message;
  bool get current =>
      mounted &&
      token == ref.read(authSessionProvider).token &&
      ref.read(authSessionProvider).isLoggedIn &&
      ref.read(authSessionProvider).isVerified &&
      widget.company == ref.read(workspaceProvider).activeCompanyId;

  @override
  void initState() {
    super.initState();
    Future.microtask(refresh);
  }

  Future<void> refresh() async {
    if (!current || busy || ref.read(workspaceProvider).isLoading) return;
    setState(() {
      loading = true;
      error = null;
      message = null;
      file = null;
      report = null;
      policy = null;
      policyError = null;
    });
    try {
      final result = await ref
          .read(parcelPdfServiceProvider)
          .details(
            token,
            widget.record,
            widget.company,
            isCurrent: () => current,
          );
      if (current) setState(() => report = result);
    } catch (failure) {
      if (current) {
        setState(
          () => error = failure.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
    if (current) {
      try {
        final result = await ref
            .read(parcelPdfServiceProvider)
            .policy(
              token,
              widget.record,
              widget.company,
              isCurrent: () => current,
            );
        if (current) {
          setState(() {
            policy = result;
            if (!result.customLogo) {
              logo = null;
              logoName = null;
            }
          });
        }
      } catch (failure) {
        if (current) {
          setState(
            () => policyError = failure.toString().replaceFirst(
              'Exception: ',
              '',
            ),
          );
        }
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> chooseLogo() async {
    if (!current || busy || policy?.customLogo != true) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery,
      );
      if (selected == null || !current) return;
      if (await selected.length() > 1024 * 1024) {
        throw Exception('Choose a PNG or JPEG logo no larger than 1 MB.');
      }
      final selectedLogo = ParcelReportLogo.fromBytes(
        await selected.readAsBytes(),
      );
      if (current) {
        setState(() {
          logo = selectedLogo;
          logoName = selected.name;
        });
      }
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

  Future<void> generate() async {
    if (!current ||
        busy ||
        loading ||
        policy?.available != true ||
        policy?.allowed != true) {
      return;
    }
    final service = ref.read(parcelPdfServiceProvider);
    if (service.pending(widget.record)) {
      setState(
        () => error =
            'Sync or resolve pending local edits before generating a report.',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generate report?'),
        content: const Text(
          'This generates a new PDF and uses the workspace report allowance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !current || busy) return;
    if (service.pending(widget.record)) {
      setState(
        () => error =
            'Sync or resolve pending local edits before generating a report.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
      message = null;
      file = null;
    });
    try {
      await service.generate(
        token,
        widget.record,
        widget.company,
        logo: logo,
        isCurrent: () => current,
      );
      if (!current) return;
      final updated = await service.details(
        token,
        widget.record,
        widget.company,
        isCurrent: () => current,
      );
      final updatedPolicy = await service.policy(
        token,
        widget.record,
        widget.company,
        isCurrent: () => current,
      );
      if (current) {
        setState(() {
          report = updated;
          policy = updatedPolicy;
          logo = null;
          logoName = null;
          message = service.pending(widget.record)
              ? 'New local edits need syncing before sharing the report.'
              : 'Report generated.';
        });
      }
    } catch (failure) {
      if (current) {
        setState(() {
          policy = null;
          policyError = 'Refresh report settings before trying again.';
          error =
              '${failure.toString().replaceFirst('Exception: ', '')} The report may have been generated; refresh before retrying.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> share(BuildContext buttonContext) async {
    if (!current ||
        busy ||
        loading ||
        report?.available != true ||
        ref.read(workspaceProvider).isLoading) {
      return;
    }
    final service = ref.read(parcelPdfServiceProvider);
    if (service.pending(widget.record)) {
      setState(
        () => error =
            'Sync or resolve pending local edits before downloading the saved report.',
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
        final result = await service.download(
          token,
          widget.record,
          widget.company,
          report!.revision!,
          isCurrent: () => current,
        );
        if (!current) return;
        file = result;
        if (result.stale && !report!.stale) {
          setState(
            () => message =
                'The record changed since this PDF was created. Review the warning before sharing.',
          );
          return;
        }
      }
      if (!mounted || !current || !buttonContext.mounted) return;
      if (service.pending(widget.record)) {
        file = null;
        throw Exception(
          'Newer local edits need syncing before sharing this report.',
        );
      }
      final box = buttonContext.findRenderObject();
      final origin = box is RenderBox && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : const Rect.fromLTWH(0, 0, 1, 1);
      final status = await service.share(file!, origin);
      if (current) {
        setState(
          () => message = status == ShareResultStatus.success
              ? 'PDF shared.'
              : 'PDF is ready to share.',
        );
      }
    } catch (failure) {
      if (current) {
        setState(
          () => error = file == null
              ? failure.toString().replaceFirst('Exception: ', '')
              : 'PDF is ready, but sharing could not be opened. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(workspaceProvider, (previous, next) {
      if (previous?.isLoading == true &&
          !next.isLoading &&
          loading &&
          report == null &&
          error == null &&
          current) {
        Future.microtask(refresh);
      }
    });
    final workspace = ref.watch(workspaceProvider);
    ref.watch(authSessionProvider);
    final available = current && !workspace.isLoading;
    final stale = report?.stale == true || file?.stale == true;
    final date = report?.generatedAt?.toLocal();
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
          title: const Text('Parcel PDF'),
          actions: [
            IconButton(
              tooltip: 'Refresh saved report',
              onPressed: available && !busy && !loading ? refresh : null,
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
                  child: Text(
                    'Workspace or account changed. Reopen the report.',
                  ),
                ),
              )
            : loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  LibraryRecordHeader(
                    icon: HugeIcons.strokeRoundedPdf01,
                    title: widget.name,
                    subtitle: workspace.label,
                  ),
                  Row(
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedPdf01,
                        size: 24,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          report?.available == true
                              ? 'Saved parcel report'
                              : 'No saved PDF',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (date != null)
                    Text(
                      'Generated ${MaterialLocalizations.of(context).formatMediumDate(date)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (stale) ...[
                    const SizedBox(height: 16),
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedAlertCircle,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This PDF contains older record details. Generate an updated report for the latest version.',
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    report?.available == true
                        ? 'Downloading this saved PDF does not generate a new report or use report-generation quota.'
                        : error == null
                        ? 'No report has been generated for this record yet.'
                        : 'Saved report details could not be loaded.',
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
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(message!),
                    ),
                  const SizedBox(height: 24),
                  if (policyError != null)
                    Text('Report settings unavailable: $policyError'),
                  if (policy != null) ...[
                    Text(
                      'Reports used: ${policy!.used} / ${policy!.limit == null
                          ? 'Not configured'
                          : policy!.limit == -1
                          ? 'Unlimited'
                          : policy!.limit}',
                    ),
                    if (!policy!.available)
                      const Text('Report generation is unavailable.'),
                    if (policy!.available && !policy!.allowed)
                      const Text(
                        'Report allowance reached or unavailable for this workspace.',
                      ),
                    if (policy!.customLogo) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: busy ? null : chooseLogo,
                        icon: const HugeIcon(
                          size: 20,
                          icon: HugeIcons.strokeRoundedImage01,
                        ),
                        label: Text(
                          logoName == null
                              ? 'Choose optional logo'
                              : 'Change logo',
                        ),
                      ),
                      if (logoName != null)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                logoName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove logo',
                              onPressed: busy
                                  ? null
                                  : () => setState(() {
                                      logo = null;
                                      logoName = null;
                                    }),
                              icon: const HugeIcon(
                                size: 20,
                                icon: HugeIcons.strokeRoundedCancel01,
                              ),
                            ),
                          ],
                        ),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: busy || !policy!.available || !policy!.allowed
                          ? null
                          : generate,
                      icon: const HugeIcon(
                        size: 20,
                        icon: HugeIcons.strokeRoundedPdf01,
                      ),
                      label: Text(
                        report?.available == true
                            ? 'Generate updated PDF'
                            : 'Generate PDF',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (report?.available == true)
                    Builder(
                      builder: (buttonContext) => FilledButton.icon(
                        onPressed: busy ? null : () => share(buttonContext),
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : HugeIcon(
                                icon: file == null
                                    ? HugeIcons.strokeRoundedDownload01
                                    : HugeIcons.strokeRoundedShare01,
                                size: 18,
                              ),
                        label: Text(
                          busy
                              ? 'Preparing...'
                              : file == null
                              ? 'Download & share PDF'
                              : 'Share PDF',
                        ),
                      ),
                    ),
                  if (error != null && report == null)
                    OutlinedButton.icon(
                      onPressed: refresh,
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedRefresh,
                        size: 18,
                      ),
                      label: const Text('Retry'),
                    ),
                ],
              ),
      ),
    );
  }
}
