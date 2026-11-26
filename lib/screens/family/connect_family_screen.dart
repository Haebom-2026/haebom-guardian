import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../app/dependencies.dart';
import '../../app/theme.dart';
import '../../repositories/guardian_repository.dart';

class ConnectFamilyScreen extends StatefulWidget {
  const ConnectFamilyScreen({super.key});

  @override
  State<ConnectFamilyScreen> createState() => _ConnectFamilyScreenState();
}

class _ConnectFamilyScreenState extends State<ConnectFamilyScreen> {
  /// 내가 가족(어르신)을 부르는 호칭 → elderLabel (보호자 앱 화면에 표시)
  static const _relations = ['어머니', '아버지', '할머니', '할아버지', '배우자', '기타'];

  /// 가족(어르신)이 나를 부르는 호칭 → guardianLabel (고령자 앱 안내 "딸에게 알림을 보냈어요")
  static const _guardianRelations = ['딸', '아들', '며느리', '사위', '손녀', '손자', '배우자', '기타'];

  final _code = TextEditingController();
  final _customRelation = TextEditingController();
  final _customGuardianRelation = TextEditingController();
  String _relation = _relations.first;

  /// 어르신 화면에 그대로 나가므로 기본값 없이 직접 고르게 한다.
  String? _guardianRelation;
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _code.dispose();
    _customRelation.dispose();
    _customGuardianRelation.dispose();
    super.dispose();
  }

  String get _relationValue => _relation == '기타' ? _customRelation.text.trim() : _relation;

  String get _guardianRelationValue =>
      _guardianRelation == '기타' ? _customGuardianRelation.text.trim() : (_guardianRelation ?? '');

  bool get _canSubmit =>
      !_submitting && _code.text.length == 6 && _relationValue.isNotEmpty && _guardianRelationValue.isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final link = await AppScope.of(context)
          .repository
          .connectWithCode(_code.text, elderLabel: _relationValue, guardianLabel: _guardianRelationValue);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${link.displayName}(${link.elderName})와(과) 연결되었습니다.')),
      );
    } on RepositoryException catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } catch (_) {
      if (mounted) setState(() => _error = '연결하지 못했습니다. 네트워크 연결을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final k = HaebomTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('가족 연결')),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.page + 4, 8, Space.page + 4, Space.page),
                children: [
                  Text(
                    '가족 휴대폰에 보이는\n연결 코드를 입력해 주세요',
                    style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '가족의 해봄 앱에서 [가족 연결]을 누르면 6자리 숫자가 나와요. 10분 동안 한 번만 쓸 수 있어요.',
                    style: t.textTheme.bodyMedium?.copyWith(color: k.textSub),
                  ),
                  const SizedBox(height: Space.section),
                  _CodeBoxes(controller: _code, hasError: _error != null, onChanged: () => setState(() => _error = null), onSubmitted: _submit),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline_rounded, size: 20, color: t.colorScheme.error),
                        const SizedBox(width: 6),
                        Expanded(child: Text(_error!, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.error))),
                      ],
                    ),
                  ],
                  const SizedBox(height: 32),
                  Text('이 가족을 뭐라고 부르나요?', style: t.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('이 앱의 알림에 표시돼요. 예) 어머니가 정부24를 사용하려고 합니다.', style: t.textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in _relations)
                        _chip(context, r, _relation == r, Key('elder_label_$r'), () => setState(() => _relation = r)),
                    ],
                  ),
                  if (_relation == '기타') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _customRelation,
                      maxLength: 10,
                      decoration: const InputDecoration(labelText: '호칭 입력 (예: 이모)'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Text('가족은 나를 뭐라고 부르나요?', style: t.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('가족의 해봄 앱 안내에 쓰여요. 예) 딸에게 알림을 보냈어요.', style: t.textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in _guardianRelations)
                        _chip(context, r, _guardianRelation == r, Key('guardian_label_$r'),
                            () => setState(() => _guardianRelation = r)),
                    ],
                  ),
                  if (_guardianRelation == '기타') ...[
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('guardian_label_custom'),
                      controller: _customGuardianRelation,
                      maxLength: 10,
                      decoration: const InputDecoration(labelText: '호칭 입력 (예: 조카)'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ],
              ),
            ),
            // 아래 고정: 연결하기
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, Space.page),
              child: FilledButton(
                key: const Key('connect_submit'),
                onPressed: _canSubmit ? _submit : null,
                child: _submitting
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('연결하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 호칭 칩: 선택되면 녹색 테두리 + 연한 녹색 바탕 + 굵은 녹색 글자
  Widget _chip(BuildContext context, String label, bool selected, Key key, VoidCallback onTap) {
    final k = HaebomTokens.of(context);
    return ChoiceChip(
      key: key,
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      backgroundColor: k.card,
      selectedColor: k.positiveBg,
      side: BorderSide(color: selected ? k.primary : k.divider, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      labelStyle: TextStyle(
        fontSize: 16,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
        color: selected ? k.primary : k.text,
      ),
      onSelected: (_) => onTap(),
    );
  }
}

/// 6칸 코드 입력. 실제 입력은 위에 겹친 투명한 TextField 하나가 받는다 (붙여넣기·자동 채우기·낭독 그대로 동작).
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({required this.controller, required this.hasError, required this.onChanged, required this.onSubmitted});
  final TextEditingController controller;
  final bool hasError;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final k = HaebomTokens.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, v, _) {
        final text = v.text;
        return Stack(
          children: [
            ExcludeSemantics(
              child: Row(
                children: [
                  for (var i = 0; i < 6; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 60,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i < text.length ? k.card : k.subtle,
                          borderRadius: BorderRadius.circular(Space.radius),
                          border: Border.all(
                            width: 1.5,
                            color: hasError
                                ? t.colorScheme.error
                                : i == text.length
                                    ? k.primary
                                    : i < text.length
                                        ? k.text
                                        : k.divider,
                          ),
                        ),
                        child: FittedBox(
                          child: Text(
                            i < text.length ? text[i] : '',
                            style: t.textTheme.headlineSmall?.copyWith(fontSize: 26),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Positioned.fill(
              child: TextField(
                key: const Key('connect_code_field'),
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                showCursor: false,
                enableInteractiveSelection: false,
                style: const TextStyle(color: Colors.transparent, fontSize: 1),
                decoration: const InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  counterText: '',
                  labelText: '연결 코드 6자리',
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  labelStyle: TextStyle(color: Colors.transparent),
                ),
                onChanged: (_) => onChanged(),
                onSubmitted: (_) => onSubmitted(),
              ),
            ),
          ],
        );
      },
    );
  }
}
