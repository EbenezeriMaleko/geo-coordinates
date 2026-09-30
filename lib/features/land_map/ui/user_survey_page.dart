import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';

import '../services/survey_queue.dart';
import '../services/survey_sync_service.dart';
import '../../../core/localization/app_localizations.dart';

class UserSurveyPage extends StatefulWidget {
  const UserSurveyPage({super.key});

  @override
  State<UserSurveyPage> createState() => _UserSurveyPageState();
}

class _UserSurveyPageState extends State<UserSurveyPage> {
  static const _roles = [
    'Surveyor',
    'Engineer',
    'Land professional',
    'Researcher',
    'Other',
  ];
  static const _difficulties = [
    'GPS accuracy',
    'Saving or editing records',
    'Offline use or syncing',
    'Navigation',
    'Coordinates or datums',
    'Finding features',
    'Nothing is difficult',
    'Other',
  ];

  final _commentController = TextEditingController();
  String? _role;
  String? _difficulty;
  int? _satisfaction;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_role == null || _difficulty == null || _satisfaction == null) {
      setState(() => _error = context.l10n.t('Please answer the three required questions.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await SurveyQueue(Hive.box('landbox')).enqueue(
        role: _role!,
        difficulty: _difficulty!,
        satisfaction: _satisfaction!,
        comment: _commentController.text,
      );
      unawaited(SurveySyncService(Hive.box('landbox')).syncPending());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = context.l10n.t('Could not save your response. Try again.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          l10n.t('Share your experience'),
          style: GoogleFonts.inter(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primary, primary.withValues(alpha: 0.84)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n.t('Help us improve TaREF'),
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.t('A few quick answers will help us understand what works and what needs attention.'),
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              children: [
                _label(l10n.t('What is your role? *')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  isExpanded: true,
                  decoration: _fieldDecoration(
                    hint: l10n.t('Select your role'),
                    icon: Icons.work_outline_rounded,
                  ),
                  items: _roles
                      .map(
                            (role) => DropdownMenuItem(
                              value: role,
                              child: Text(l10n.t(role)),
                            ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _role = value),
                ),
                const SizedBox(height: 20),
                _label(l10n.t('What is most difficult? *')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _difficulty,
                  isExpanded: true,
                  decoration: _fieldDecoration(
                    hint: l10n.t('Choose one area'),
                    icon: Icons.help_outline_rounded,
                  ),
                  items: _difficulties
                      .map(
                        (difficulty) => DropdownMenuItem(
                          value: difficulty,
                          child: Text(l10n.t(difficulty)),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _difficulty = value),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _sectionCard(
              children: [
                _label(l10n.t('Overall, how satisfied are you? *')),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (var score = 1; score <= 5; score++) ...[
                      if (score > 1) const SizedBox(width: 8),
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: _satisfaction == score,
                          label: l10n.satisfaction(score),
                          child: InkWell(
                            onTap: _saving
                                ? null
                                : () => setState(() => _satisfaction = score),
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _satisfaction == score
                                    ? primary
                                    : const Color(0xFFF9FAFB),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _satisfaction == score
                                      ? primary
                                      : const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: Text(
                                '$score',
                                style: GoogleFonts.inter(
                                  color: _satisfaction == score
                                      ? Colors.white
                                      : const Color(0xFF374151),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _hint(l10n.t('Very dissatisfied')),
                    _hint(l10n.t('Very satisfied')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            _sectionCard(
              children: [
                _label(l10n.t('Anything else? (optional)')),
                const SizedBox(height: 8),
                TextField(
                  controller: _commentController,
                  enabled: !_saving,
                  maxLength: 1000,
                  minLines: 3,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _fieldDecoration(
                    hint: l10n.t('Tell us more about your experience'),
                    icon: Icons.notes_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF1F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.t('Optional survey. No coordinates or saved records are collected. Your response stays on this device until it can be sent. We will retry automatically when the server is available.'),
                      style: GoogleFonts.inter(
                        color: const Color(0xFF374151),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEECEC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: GoogleFonts.inter(
                    color: const Color(0xFFB42318),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                _saving ? l10n.t('Saving…') : l10n.t('Save response'),
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEAECEF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: GoogleFonts.inter(
      color: const Color(0xFF374151),
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _hint(String text) =>
      Text(text, style: GoogleFonts.inter(color: Colors.black54, fontSize: 11));

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 14),
      prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 20),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF001F3F), width: 1.8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}
