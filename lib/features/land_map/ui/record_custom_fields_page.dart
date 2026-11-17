import '../../widget/plan_access_lock.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../core/network/api_client.dart';
import '../../auth/providers/auth_provider.dart';
import '../../workspaces/workspace_provider.dart';
import '../../workspaces/workspace_page_style.dart';
import '../services/record_recovery_service.dart';

class RecordCustomFieldsPage extends ConsumerStatefulWidget {
  const RecordCustomFieldsPage({
    super.key,
    required this.record,
    required this.company,
    this.client,
  });
  final String record;
  final int? company;
  final http.Client? client;

  @override
  ConsumerState<RecordCustomFieldsPage> createState() =>
      _RecordCustomFieldsPageState();
}

class _RecordCustomFieldsPageState
    extends ConsumerState<RecordCustomFieldsPage> {
  late final client = widget.client ?? http.Client();
  final form = GlobalKey<FormState>();
  final controllers = <TextEditingController>[];
  List<Map<String, dynamic>> fields = [];
  late final String token;
  String? revision;
  String? error;
  bool busy = false;
  bool editable = false;
  bool changed = false;

  bool get current =>
      mounted &&
      ref.read(authSessionProvider).token == token &&
      ref.read(authSessionProvider).isVerified &&
      ref.read(workspaceProvider).activeCompanyId == widget.company &&
      !ref.read(workspaceProvider).isLoading;
  bool get pending => RecordRecoveryService().pending(widget.record);

  Future<bool> confirmDiscard() async {
    if (!changed) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard unsaved changes?'),
            content: const Text('Your custom-field edits have not been saved.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ==
        true;
  }

  Future<void> refresh() async {
    if (busy || !await confirmDiscard() || !current) return;
    await load();
  }

  @override
  void initState() {
    super.initState();
    token = ref.read(authSessionProvider).token;
    Future.microtask(() => load());
  }

  @override
  void dispose() {
    client.close();
    for (final controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> load({bool save = false}) async {
    if (!current ||
        busy ||
        (save && (pending || !editable || revision == null))) {
      return;
    }
    if (save && form.currentState?.validate() != true) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final headers = ApiClient.jsonHeaders(bearerToken: token)
        ..remove('X-Company-Id');
      if (widget.company != null) headers['X-Company-Id'] = '${widget.company}';
      final request =
          http.Request(
              save ? 'PUT' : 'GET',
              ApiClient.uri('/lands/${widget.record}/custom-fields'),
            )
            ..followRedirects = false
            ..headers.addAll(headers);
      if (save) {
        request.body = jsonEncode({
          'revision': revision,
          'fields': [
            for (var i = 0; i < fields.length; i++)
              {
                'name': fields[i]['name'],
                'type': fields[i]['type'],
                'value': fields[i]['type'] == 'boolean'
                    ? fields[i]['value']
                    : fields[i]['type'] == 'number'
                    ? num.tryParse(controllers[i].text.trim())
                    : fields[i]['type'] == 'date' && controllers[i].text.isEmpty
                    ? null
                    : controllers[i].text,
              },
          ],
        });
      }
      final streamed = await client.send(request).timeout(ApiClient.timeout);
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(ApiClient.timeout);
      if (!current) return;
      final decoded = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errors = decoded is Map ? decoded['errors'] : null;
        final messages = errors is Map
            ? errors.values
                  .whereType<List>()
                  .expand((v) => v)
                  .whereType<String>()
                  .toList()
            : <String>[];
        throw Exception(
          messages.isNotEmpty
              ? messages.first
              : decoded is Map
              ? decoded['message'] ?? 'Request failed. Refresh before retrying.'
              : 'Request failed.',
        );
      }
      final data = decoded is Map ? decoded['data'] : null;
      if (data is! Map ||
          data['fields'] is! List ||
          data['revision'] is! String ||
          data['policy'] is! Map) {
        throw Exception('Invalid custom-field response.');
      }
      final loaded = (data['fields'] as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
      for (final field in loaded) {
        if (!['text', 'number', 'date', 'boolean'].contains(field['type'])) {
          throw Exception('An unsupported field type requires a newer app.');
        }
      }
      for (final controller in controllers) {
        controller.dispose();
      }
      controllers.clear();
      controllers.addAll(
        loaded.map(
          (f) => TextEditingController(text: f['value']?.toString() ?? ''),
        ),
      );
      setState(() {
        fields = loaded;
        revision = data['revision'];
        editable =
            data['can_edit_record'] == true &&
            data['policy']['editable'] == true;
        changed = false;
      });
      if (save && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Custom fields saved.')));
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

  Color get accent => widget.company != null
      ? const Color(0xFF001F3F)
      : const Color(0xFF001F3F);

  InputDecoration fieldDecoration(int index) {
    final type = fields[index]['type'];
    final icon = switch (type) {
      'number' => HugeIcons.strokeRoundedCalculator01,
      'date' => HugeIcons.strokeRoundedCalendar03,
      'boolean' => HugeIcons.strokeRoundedCheckmarkCircle02,
      _ => HugeIcons.strokeRoundedNote01,
    };
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      labelText: fields[index]['name'].toString(),
      filled: true,
      fillColor: const Color(0xFFF7F7F8),
      border: border(const Color(0xFFE8ECF0)),
      enabledBorder: border(const Color(0xFFE8ECF0)),
      disabledBorder: border(const Color(0xFFE8ECF0)),
      focusedBorder: border(accent, 1.5),
      floatingLabelStyle: TextStyle(color: accent, fontWeight: FontWeight.w600),
      prefixIcon: SizedBox(
        width: 48,
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: HugeIcon(icon: icon, size: 20, color: accent),
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    );
  }

  Widget notice({
    required dynamic icon,
    required String title,
    String? subtitle,
    bool isError = false,
  }) {
    final color = isError ? const Color(0xFFB42318) : accent;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HugeIcon(icon: icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.black54,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authSessionProvider);
    ref.watch(workspaceProvider);
    final enabled = current && editable && !busy && !pending;
    return PopScope(
      canPop: !changed && !busy,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || busy || !await confirmDiscard() || !mounted) return;
        setState(() => changed = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      },
      child: WorkspaceScaffold(
        company: widget.company != null,
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedArrowLeft01,
              size: 22,
              color: accent,
            ),
          ),
          title: const Text('Custom fields'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: busy ? null : refresh,
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedRefresh,
                size: 20,
                color: accent,
              ),
            ),
          ],
        ),
        body: !current
            ? const Center(
                child: Text(
                  'Workspace or account changed. Reopen this record.',
                ),
              )
            : Form(
                key: form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE8ECF0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: HugeIcon(
                              icon: HugeIcons.strokeRoundedNote01,
                              size: 22,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Record details',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Additional information for this location.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.black54,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (busy)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: LinearProgressIndicator(color: accent),
                      ),
                    if (error != null)
                      notice(
                        icon: HugeIcons.strokeRoundedAlertCircle,
                        title: error!,
                        isError: true,
                      ),
                    if (pending)
                      notice(
                        icon: HugeIcons.strokeRoundedCloud,
                        title:
                            'Sync pending edits before saving custom fields.',
                      ),
                    if (revision != null && !editable)
                      notice(
                        icon: HugeIcons.strokeRoundedLockKey,
                        title:
                            'These fields are read-only under the current record access or plan.',
                      ),
                    if (revision != null && fields.isEmpty)
                      notice(
                        icon: HugeIcons.strokeRoundedNote01,
                        title: 'No custom fields',
                        subtitle: 'Custom fields can be configured on the web.',
                      ),
                    for (var i = 0; i < fields.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: fields[i]['type'] == 'boolean'
                            ? PlanAccessLock(
                                locked: revision != null && !editable && !busy,
                                child: DropdownButtonFormField<bool>(
                                  initialValue: fields[i]['value'] as bool?,
                                  decoration: fieldDecoration(i),
                                  items: const [
                                    DropdownMenuItem<bool>(
                                      value: null,
                                      child: Text('Not set'),
                                    ),
                                    DropdownMenuItem(
                                      value: true,
                                      child: Text('Yes'),
                                    ),
                                    DropdownMenuItem(
                                      value: false,
                                      child: Text('No'),
                                    ),
                                  ],
                                  onChanged: enabled
                                      ? (value) => setState(() {
                                          fields[i]['value'] = value;
                                          changed = true;
                                        })
                                      : null,
                                ),
                              )
                            : PlanAccessLock(
                                locked: revision != null && !editable && !busy,
                                child: TextFormField(
                                  controller: controllers[i],
                                  enabled: enabled,
                                  maxLength: fields[i]['type'] == 'text'
                                      ? 2000
                                      : null,
                                  keyboardType: fields[i]['type'] == 'number'
                                      ? const TextInputType.numberWithOptions(
                                          decimal: true,
                                          signed: true,
                                        )
                                      : TextInputType.text,
                                  decoration: fieldDecoration(i).copyWith(
                                    hintText: fields[i]['type'] == 'date'
                                        ? 'YYYY-MM-DD'
                                        : null,
                                    suffixIcon: fields[i]['type'] == 'date'
                                        ? IconButton(
                                            tooltip: 'Choose date',
                                            icon: HugeIcon(
                                              icon: HugeIcons
                                                  .strokeRoundedCalendar03,
                                              size: 20,
                                              color: accent,
                                            ),
                                            onPressed: !enabled
                                                ? null
                                                : () async {
                                                    final chosen =
                                                        await showDatePicker(
                                                          context: context,
                                                          initialDate:
                                                              DateTime.tryParse(
                                                                controllers[i]
                                                                    .text,
                                                              ) ??
                                                              DateTime.now(),
                                                          firstDate: DateTime(
                                                            1,
                                                          ),
                                                          lastDate: DateTime(
                                                            9999,
                                                            12,
                                                            31,
                                                          ),
                                                        );
                                                    if (chosen == null ||
                                                        !current ||
                                                        busy) {
                                                      return;
                                                    }
                                                    setState(() {
                                                      controllers[i].text =
                                                          chosen
                                                              .toIso8601String()
                                                              .substring(0, 10);
                                                      changed = true;
                                                    });
                                                  },
                                          )
                                        : null,
                                  ),
                                  onChanged: (_) =>
                                      setState(() => changed = true),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return null;
                                    }
                                    if (fields[i]['type'] == 'number') {
                                      final number = num.tryParse(value.trim());
                                      if (number == null ||
                                          !number.isFinite ||
                                          number.abs() > 999999999999999) {
                                        return 'Enter a valid number.';
                                      }
                                    }
                                    if (fields[i]['type'] == 'date') {
                                      final date = DateTime.tryParse(value);
                                      if (date == null ||
                                          date.toIso8601String().substring(
                                                0,
                                                10,
                                              ) !=
                                              value) {
                                        return 'Enter a valid date as YYYY-MM-DD.';
                                      }
                                    }
                                    return null;
                                  },
                                ),
                              ),
                      ),
                    if (fields.isNotEmpty)
                      PlanAccessLock(
                        locked: revision != null && !editable && !busy,
                        child: FilledButton.icon(
                          onPressed: enabled && changed
                              ? () => load(save: true)
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedFloppyDisk,
                            size: 20,
                          ),
                          label: const Text('Save changes'),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
