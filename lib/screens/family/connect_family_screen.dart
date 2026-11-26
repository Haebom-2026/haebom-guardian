import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../app/dependencies.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('가족 연결')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('연결 코드 입력', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              '가족의 해봄 앱에서 [가족 연결]을 누르면 6자리 숫자 코드가 표시됩니다. '
              '코드는 10분 동안 한 번만 사용할 수 있습니다.',
              style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('connect_code_field'),
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: t.textTheme.headlineMedium?.copyWith(letterSpacing: 10, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: '000000',
                counterText: '',
                errorText: _error,
                errorMaxLines: 3,
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            Text('가족을 부르는 호칭', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('이 앱의 알림에 표시됩니다. 예) 어머니가 정부24를 사용하려고 합니다.',
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in _relations)
                  ChoiceChip(
                    label: Text(r),
                    selected: _relation == r,
                    key: Key('elder_label_$r'),
                    onSelected: (_) => setState(() => _relation = r),
                  ),
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
            const SizedBox(height: 24),
            Text('가족이 나를 부르는 호칭', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('가족의 해봄 앱 안내에 쓰입니다. 예) 딸에게 알림을 보냈어요.',
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in _guardianRelations)
                  ChoiceChip(
                    key: Key('guardian_label_$r'),
                    label: Text(r),
                    selected: _guardianRelation == r,
                    onSelected: (_) => setState(() => _guardianRelation = r),
                  ),
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
            const SizedBox(height: 28),
            FilledButton(
              key: const Key('connect_submit'),
              onPressed: _canSubmit ? _submit : null,
              child: _submitting
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('연결하기'),
            ),
          ],
        ),
      ),
    );
  }
}
