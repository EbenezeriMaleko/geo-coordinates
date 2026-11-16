import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import '../widget/app_backarrow.dart'; // adjust to your file name/path
import '../workspaces/workspace_provider.dart';
import 'entitlement_provider.dart';
import 'subscription_provider.dart';

const Color _personalAccent = Color(0xFF001F3F);
const Color _companyAccent = Color(0xFF245B83);
const Color _pageBackground = Color(0xFFF7F7F8);
const Color _cardBorder = Color(0xFFE8ECF0);
const Color _green = Color(0xFF1B7F4B);
const Color _greenSoft = Color(0xFFE6F5EC);

// ── Formatting helpers ─────────────────────────────────────────────

String _thousands(String digits) => digits.replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

String _money(dynamic currency, dynamic price) {
  final n = num.tryParse('$price');
  final c = currency?.toString() ?? '';
  if (n == null) {
    return [c, price?.toString() ?? ''].where((e) => e.isNotEmpty).join(' ');
  }
  if (n == 0) return 'Free';
  final s = n == n.roundToDouble()
      ? n.toInt().toString()
      : n.toStringAsFixed(2);
  final parts = s.split('.');
  parts[0] = _thousands(parts[0]);
  final formatted = parts.join('.');
  return c.isEmpty ? formatted : '$c $formatted';
}

String _interval(dynamic value) {
  final s = value?.toString().toLowerCase() ?? '';
  switch (s) {
    case 'monthly':
    case 'month':
      return 'month';
    case 'yearly':
    case 'annual':
    case 'annually':
    case 'year':
      return 'year';
    case 'weekly':
    case 'week':
      return 'week';
    case 'daily':
    case 'day':
      return 'day';
    default:
      return s;
  }
}

String _priceLabel(Map plan) {
  final i = _interval(plan['billing_interval']);
  final m = _money(plan['currency'], plan['price']);
  return (i.isEmpty || m == 'Free') ? m : '$m / $i';
}
// ── Feature extraction ─────────────────────────────────────────────
// Reads plan['features'], ['entitlements'], ['limits'] and ['quotas'].
// Each may be a list of strings, a list of maps, or a key/value map.

class _Feature {
  final String label;
  final String? value;
  final bool included;
  const _Feature(this.label, this.value, this.included);
}

String _humanize(String key) {
  var s = key.replaceAll(RegExp(r'[_\-.]+'), ' ').trim();
  s = s.replaceFirst(RegExp(r'^(max|limit)\s+', caseSensitive: false), '');
  if (s.isEmpty) return key;
  return s[0].toUpperCase() + s.substring(1).toLowerCase();
}

String? _formatValue(String key, dynamic v) {
  if (v == null) return null;
  if (v is num) {
    if (v == -1) return 'Unlimited';
    final lower = key.toLowerCase();
    if (lower.contains('storage') || lower.contains('bytes')) {
      if (v >= 1073741824) {
        return '${(v / 1073741824).toStringAsFixed(v % 1073741824 == 0 ? 0 : 1)} GB';
      }
      if (v >= 1048576) return '${(v / 1048576).round()} MB';
      return '${_thousands(v.toInt().toString())} MB';
    }
    return v == v.roundToDouble()
        ? _thousands(v.toInt().toString())
        : v.toStringAsFixed(1);
  }
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

_Feature? _fromEntry(String key, dynamic v) {
  final label = _humanize(key);
  if (v == null) return null;
  if (v is bool) return _Feature(label, null, v);
  if (v is num) return _Feature(label, _formatValue(key, v), v != 0);
  if (v is String) {
    final lower = v.toLowerCase();
    if (lower == 'true') return _Feature(label, null, true);
    if (lower == 'false') return _Feature(label, null, false);
    return _Feature(label, _formatValue(key, v), true);
  }
  if (v is Map) {
    final enabled = v['enabled'] ?? v['included'] ?? v['is_enabled'];
    final limit = v['limit'] ?? v['value'];
    return _Feature(
      label,
      _formatValue(key, limit),
      enabled is bool ? enabled : true,
    );
  }
  return null;
}

List<_Feature> _parseSource(dynamic raw) {
  final out = <_Feature>[];
  if (raw is List) {
    for (final item in raw) {
      if (item is String && item.trim().isNotEmpty) {
        out.add(_Feature(item.trim(), null, true));
      } else if (item is Map) {
        final label =
            (item['label'] ??
                    item['name'] ??
                    item['title'] ??
                    item['feature'] ??
                    item['key'])
                ?.toString();
        if (label == null || label.isEmpty) continue;
        final enabled = item['enabled'] ?? item['included'] ?? item['is_enabled'];
        final key = (item['key'] ?? label).toString();
        out.add(
          _Feature(
            label == key ? _humanize(label) : label,
            _formatValue(key, item['value'] ?? item['limit']),
            enabled is bool ? enabled : true,
          ),
        );
      }
    }
  } else if (raw is Map) {
    raw.forEach((k, v) {
      final f = _fromEntry(k.toString(), v);
      if (f != null) out.add(f);
    });
  }
  return out;
}

List<_Feature> _featuresOf(Map plan) {
  final seen = <String>{};
  final result = <_Feature>[];
  for (final source in const [
    'features',
    'entitlements',
    'limits',
    'quotas',
  ]) {
    for (final f in _parseSource(plan[source])) {
      if (seen.add(f.label.toLowerCase())) result.add(f);
    }
  }
  // Included features first, excluded ones last.
  result.sort((a, b) {
    if (a.included == b.included) return 0;
    return a.included ? -1 : 1;
  });
  return result;
}

// ── Page ───────────────────────────────────────────────────────────

class PlansCatalogPage extends ConsumerStatefulWidget {
  const PlansCatalogPage({super.key});

  @override
  ConsumerState<PlansCatalogPage> createState() => _PlansCatalogPageState();
}

class _PlansCatalogPageState extends ConsumerState<PlansCatalogPage> {
  PageController? _controller;
  int _selected = 0;
  bool _busy = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

    Future<bool> _confirmRequest(Map plan, String? currentName) async {
    final isCompany = ref.read(workspaceProvider).activeCompanyId != null;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _RequestSheet(
        accent: isCompany ? _companyAccent : _personalAccent,
        planName: '${plan['name']}',
        currentName: currentName,
        priceLabel: _priceLabel(plan),
        workspaceLabel: ref.read(workspaceProvider).label,
        featureCount: _featuresOf(plan).where((f) => f.included).length,
      ),
    );
    return result == true;
  }

  Future<void> _request(Map plan, String? currentName) async {
    if (_busy) return;
    final session = ref.read(authSessionProvider);
    final company = ref.read(workspaceProvider).activeCompanyId;
    final confirmed = await _confirmRequest(plan, currentName);
    if (!mounted ||
        !confirmed ||
        company != ref.read(workspaceProvider).activeCompanyId ||
        session.token != ref.read(authSessionProvider).token) {
      return;
    }
    setState(() => _busy = true);
    try {
      final response = await ApiClient.postJson(
        '/billing/requests',
        bearerToken: session.token,
        body: {'subscription_plan_id': plan['id'], 'company_id': company},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = jsonDecode(response.body);
        throw Exception(
          body is Map
              ? body['message'] ?? 'Request failed.'
              : 'Request failed.',
        );
      }
      if (!mounted) return;
      ref.invalidate(subscriptionOverviewProvider);
      ref.invalidate(entitlementProvider);
      ref.invalidate(workspaceAccessSnapshotProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan request submitted for approval.')),
      );
      Navigator.of(context).maybePop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit request: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(subscriptionOverviewProvider);
    final isCompany = ref.watch(workspaceProvider).activeCompanyId != null;
    final accent = isCompany ? _companyAccent : _personalAccent;
    final baseTheme = Theme.of(context);

    return Theme(
      data: baseTheme.copyWith(
        colorScheme: baseTheme.colorScheme.copyWith(primary: accent),
      ),
      child: Scaffold(
        backgroundColor: _pageBackground,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          leading: const AppBackButton(),
          title: const Text(
            'Available plans',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        body: overview.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const HugeIcon(
                    icon: HugeIcons.strokeRoundedWifiOff01,
                    color: Colors.black26,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Plans are unavailable',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () => ref.invalidate(subscriptionOverviewProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
          data: (data) {
            final plans = data['plans'] is List
                ? (data['plans'] as List).whereType<Map>().toList()
                : <Map>[];
            if (plans.isEmpty) {
              return const Center(
                child: Text(
                  'No plans are available yet.',
                  style: TextStyle(color: Colors.black54),
                ),
              );
            }

            final subscription = data['subscription'] is Map
                ? data['subscription'] as Map
                : null;
            final currentPlan = subscription?['plan'] is Map
                ? subscription!['plan'] as Map
                : null;
            final currentId = currentPlan?['id']?.toString();
            final pending = data['has_pending_request'] == true;
            final canRequest = data['can_request'] == true && !pending;

            if (_controller == null) {
              final idx = currentId == null
                  ? 0
                  : plans.indexWhere((p) => p['id']?.toString() == currentId);
              _selected = idx < 0 ? 0 : idx;
              _controller = PageController(
                viewportFraction: 0.9,
                initialPage: _selected,
              );
            }
            final selectedIndex = _selected.clamp(0, plans.length - 1);
            final selectedPlan = plans[selectedIndex];
            final selectedIsCurrent =
                currentId != null &&
                selectedPlan['id']?.toString() == currentId;

            final String buttonLabel;
            final bool buttonEnabled;
            if (selectedIsCurrent) {
              buttonLabel = 'Current plan';
              buttonEnabled = false;
            } else if (pending) {
              buttonLabel = 'Pending approval';
              buttonEnabled = false;
            } else if (!canRequest) {
              buttonLabel = 'Unavailable';
              buttonEnabled = false;
            } else {
              buttonLabel = 'Request ${selectedPlan['name']}';
              buttonEnabled = !_busy;
            }

            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 14, 24, 6),
                  child: Text(
                    'Swipe to compare plans. Requests are reviewed by an administrator.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.black54,
                      height: 1.35,
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: plans.length,
                    onPageChanged: (i) => setState(() => _selected = i),
                    itemBuilder: (context, index) {
                      final plan = plans[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 10,
                        ),
                        child: _PlanDetailCard(
                          plan: plan,
                          isCurrent:
                              currentId != null &&
                              plan['id']?.toString() == currentId,
                        ),
                      );
                    },
                  ),
                ),
                if (plans.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < plans.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == selectedIndex ? 20 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == selectedIndex
                                  ? accent
                                  : Colors.black12,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                      ],
                    ),
                  ),
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: _cardBorder)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${selectedPlan['name']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _interval(selectedPlan['billing_interval'])
                                          .isEmpty
                                      ? _money(
                                          selectedPlan['currency'],
                                          selectedPlan['price'],
                                        )
                                      : '${_money(selectedPlan['currency'], selectedPlan['price'])} / ${_interval(selectedPlan['billing_interval'])}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: FilledButton.icon(
                              onPressed: buttonEnabled
                                ? () => _request(
                                    selectedPlan,
                                    currentPlan?['name']?.toString(),
                                  )
                                : null,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 13,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: _busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : HugeIcon(
                                      icon: selectedIsCurrent
                                          ? HugeIcons.strokeRoundedTick02
                                          : HugeIcons.strokeRoundedSent,
                                      color: buttonEnabled || _busy
                                          ? Colors.white
                                          : Colors.black38,
                                      size: 18,
                                    ),
                              label: Text(
                                buttonLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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

// ── Plan card ──────────────────────────────────────────────────────

class _PlanDetailCard extends StatelessWidget {
  const _PlanDetailCard({required this.plan, required this.isCurrent});
  final Map plan;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final interval = _interval(plan['billing_interval']);
    final description = plan['description'];
    final features = _featuresOf(plan);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isCurrent ? accent.withValues(alpha: 0.45) : _cardBorder,
          width: isCurrent ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedCrown,
                      color: accent,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${plan['name']}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  if (isCurrent)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Current plan',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: _money(plan['currency'], plan['price']),
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                    if (interval.isNotEmpty)
                      TextSpan(
                        text: '  / $interval',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                  ],
                ),
              ),
              if (description is String && description.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Colors.black54,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const Divider(height: 1, color: Color(0xFFEEF1F4)),
              const SizedBox(height: 16),
              const Text(
                "WHAT'S INCLUDED",
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: Colors.black45,
                ),
              ),
              const SizedBox(height: 8),
              if (features.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    "Feature details for this plan aren't available yet.",
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                )
              else
                for (final f in features) _FeatureRow(feature: f),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.feature});
  final _Feature feature;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final included = feature.included;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: included ? _greenSoft : const Color(0xFFF1F3F5),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: HugeIcon(
              icon: included
                  ? HugeIcons.strokeRoundedTick02
                  : HugeIcons.strokeRoundedCancel01,
              color: included ? _green : Colors.black38,
              size: 14,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              feature.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: included ? Colors.black87 : Colors.black38,
              ),
            ),
          ),
          if (feature.value != null) ...[
            const SizedBox(width: 8),
            Text(
              feature.value!,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: included ? accent : Colors.black38,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RequestSheet extends StatelessWidget {
  const _RequestSheet({
    required this.accent,
    required this.planName,
    required this.currentName,
    required this.priceLabel,
    required this.workspaceLabel,
    required this.featureCount,
  });

  final Color accent;
  final String planName;
  final String? currentName;
  final String priceLabel;
  final String workspaceLabel;
  final int featureCount;

  Widget _side(String label, String name, {bool highlight = false}) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
            color: Colors.black45,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: highlight ? accent : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(int number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.35,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD5DCE5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedSent,
                color: accent,
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Request $planName?',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your request will be sent to an administrator for review.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 18),

            // From → To summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _cardBorder),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _side('CURRENT', currentName ?? 'No plan')),
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: _cardBorder),
                        ),
                        alignment: Alignment.center,
                        child: const HugeIcon(
                          icon: HugeIcons.strokeRoundedArrowRight01,
                          color: Colors.black54,
                          size: 16,
                        ),
                      ),
                      Expanded(
                        child: _side('REQUESTED', planName, highlight: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFE8ECF0)),
                  const SizedBox(height: 6),
                  _detail('Price', priceLabel),
                  _detail('Workspace', workspaceLabel),
                  if (featureCount > 0)
                    _detail('Features included', '$featureCount'),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // What happens next
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'WHAT HAPPENS NEXT',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: Colors.black45,
                ),
              ),
            ),
            const SizedBox(height: 6),
            _step(1, 'An administrator reviews your request.'),
            _step(2, "You'll see the status in Plans & Access."),
            _step(3, 'Your access updates once it is approved.'),
            const SizedBox(height: 14),

            // Reassurance
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _greenSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedShield01,
                    color: _green,
                    size: 18,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Submitting does not charge you. Your current access stays the same until the request is approved.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedSent,
                  color: Colors.white,
                  size: 18,
                ),
                label: const Text(
                  'Submit request',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}