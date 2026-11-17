import '../../widget/plan_access_lock.dart';
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
          centerTitle: true,
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
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LibraryRecordHeader(
                      icon: HugeIcons.strokeRoundedLocation01,
                      title: widget.name,
                      subtitle: workspace.label,
                    ),
                    if (error != null)
                      _PdfNotice(
                        icon: HugeIcons.strokeRoundedAlertCircle,
                        text: error!,
                        color: const Color(0xFFB42318),
                      ),
                    if (message != null)
                      _PdfNotice(
                        icon: HugeIcons.strokeRoundedCheckmarkCircle02,
                        text: message!,
                        color: const Color(0xFF1B7F4B),
                      ),
                    _PdfSection(
                      icon: HugeIcons.strokeRoundedPdf01,
                      title: report?.available == true
                          ? 'Saved parcel report'
                          : 'No saved PDF',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (date != null) ...[
                            Row(
                              children: [
                                const HugeIcon(
                                  icon: HugeIcons.strokeRoundedCalendar03,
                                  size: 16,
                                  color: Colors.black45,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Generated ${MaterialLocalizations.of(context).formatMediumDate(date)}',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (stale)
                            const _PdfNotice(
                              icon: HugeIcons.strokeRoundedAlertCircle,
                              text:
                                  'This PDF contains older record details. Generate an updated report for the latest version.',
                              color: Color(0xFFB26A00),
                            ),
                          Text(
                            report?.available == true
                                ? 'Downloading this saved PDF does not generate a new report or use report-generation quota.'
                                : error == null
                                ? 'No report has been generated for this record yet.'
                                : 'Saved report details could not be loaded.',
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: Colors.black54,
                            ),
                          ),
                          if (report?.available == true) ...[
                            const SizedBox(height: 20),
                            Builder(
                              builder: (buttonContext) => FilledButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => share(buttonContext),
                                icon: busy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : HugeIcon(
                                        icon: file == null
                                            ? HugeIcons.strokeRoundedDownload01
                                            : HugeIcons.strokeRoundedShare01,
                                        size: 20,
                                      ),
                                label: Text(
                                  busy
                                      ? 'Preparing...'
                                      : file == null
                                      ? 'Download & share PDF'
                                      : 'Share PDF',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                          if (error != null && report == null) ...[
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: busy ? null : refresh,
                              icon: const HugeIcon(
                                icon: HugeIcons.strokeRoundedRefresh,
                                size: 18,
                              ),
                              label: const Text('Retry'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (policyError != null)
                      _PdfNotice(
                        icon: HugeIcons.strokeRoundedAlertCircle,
                        text: 'Report settings unavailable: $policyError',
                        color: const Color(0xFFB26A00),
                      ),
                    if (policy != null)
                      _PdfSection(
                        icon: HugeIcons.strokeRoundedSettings01,
                        title: 'Generate report',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F7F8),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Reports used: ${policy!.used} / ${policy!.limit == null
                                    ? 'Not configured'
                                    : policy!.limit == -1
                                    ? 'Unlimited'
                                    : policy!.limit}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (!policy!.available) ...[
                              const SizedBox(height: 12),
                              const Text(
                                'Report generation is unavailable.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.black54,
                                  height: 1.4,
                                ),
                              ),
                            ],
                            if (policy!.available && !policy!.allowed) ...[
                              const SizedBox(height: 12),
                              const Text(
                                'Report allowance reached or unavailable for this workspace.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.black54,
                                  height: 1.4,
                                ),
                              ),
                            ],
                            ...[
                              const SizedBox(height: 20),
                              const Text(
                                'REPORT LOGO',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  letterSpacing: 0.6,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black45,
                                ),
                              ),
                              const SizedBox(height: 8),
                              PlanAccessLock(
                                locked: !busy && !policy!.customLogo,
                                child: OutlinedButton.icon(
                                  onPressed: busy ? null : chooseLogo,
                                  icon: const HugeIcon(
                                    icon: HugeIcons.strokeRoundedImage01,
                                    size: 20,
                                  ),
                                  label: Text(
                                    logoName == null
                                        ? 'Choose optional logo'
                                        : 'Change logo',
                                  ),
                                ),
                              ),
                              if (logoName != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    children: [
                                      const HugeIcon(
                                        icon: HugeIcons.strokeRoundedImage01,
                                        size: 16,
                                        color: Colors.black45,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          logoName!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            color: Colors.black54,
                                          ),
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
                                          icon: HugeIcons.strokeRoundedCancel01,
                                          size: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                            const SizedBox(height: 20),
                            PlanAccessLock(
                              locked:
                                  !busy &&
                                  (!policy!.available || !policy!.allowed),
                              child: OutlinedButton.icon(
                                onPressed:
                                    busy ||
                                        !policy!.available ||
                                        !policy!.allowed
                                    ? null
                                    : generate,
                                icon: const HugeIcon(
                                  icon: HugeIcons.strokeRoundedPdf01,
                                  size: 20,
                                ),
                                label: Text(
                                  report?.available == true
                                      ? 'Generate updated PDF'
                                      : 'Generate PDF',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _PdfSection extends StatelessWidget {
  const _PdfSection({
    required this.icon,
    required this.title,
    required this.child,
  });
  final dynamic icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8ECF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: HugeIcon(icon: icon, size: 20, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _PdfNotice extends StatelessWidget {
  const _PdfNotice({
    required this.icon,
    required this.text,
    required this.color,
  });
  final dynamic icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.18)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HugeIcon(icon: icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, color: color, height: 1.45),
          ),
        ),
      ],
    ),
  );
}
