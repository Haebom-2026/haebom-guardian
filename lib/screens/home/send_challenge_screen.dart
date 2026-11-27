import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../controllers/guardian_store.dart';
import '../../models/challenge.dart';
import '../../repositories/guardian_repository.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';

Future<void> openSendChallenge(BuildContext context, GuardianStore store, {String? elderId}) async {
  if (store.links.isEmpty) return;
  final sentTo = await Navigator.push<String>(
    context,
    MaterialPageRoute(
      builder: (_) => SendChallengeScreen(store: store, elderId: elderId),
    ),
  );
  if (sentTo != null && context.mounted) {
    showMessage(
      context,
      '${store.nameOf(sentTo)}께 도전을 보냈어요. 하실지는 ${withSubjectParticle(store.nameOf(sentTo))} 직접 정해요.',
    );
  }
}

/// 도전 보내기: 보호자가 이름·도움말을 직접 쓴다 (예시를 눌러 고쳐 써도 된다).
/// 아래 미리 보기는 어르신 폰에서 보일 모습 — 큰 글씨, 버튼 두 개.
class SendChallengeScreen extends StatefulWidget {
  const SendChallengeScreen({super.key, required this.store, this.elderId});
  final GuardianStore store;
  final String? elderId;

  @override
  State<SendChallengeScreen> createState() => _SendChallengeScreenState();
}

class _SendChallengeScreenState extends State<SendChallengeScreen> {
  final _title = TextEditingController();
  final _hint = TextEditingController();
  late String _elder = widget.elderId ?? widget.store.links.first.elderId;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(_changed);
    _hint.addListener(_changed);
  }

  void _changed() => setState(() => _error = null);

  @override
  void dispose() {
    _title.dispose();
    _hint.dispose();
    super.dispose();
  }

  void _useExample(ChallengeTemplate t) {
    _title.text = t.title;
    _hint.text = t.hint;
  }

  Future<void> _send() async {
    final problem = validateChallenge(_title.text, _hint.text);
    if (problem != null) return setState(() => _error = problem);
    setState(() => _sending = true);
    try {
      await widget.store.suggestChallenge(_elder, _title.text, hint: _hint.text);
      if (mounted) Navigator.pop(context, _elder);
    } on RepositoryException catch (e) {
      if (mounted) setState(() => _error = e.detail ?? e.userMessage);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final k = HaebomTokens.of(context);
    final store = widget.store;
    final name = store.nameOf(_elder);
    final from = store.linkFor(_elder)?.guardianLabel.trim() ?? '';
    final problem = _title.text.trim().isEmpty ? null : validateChallenge(_title.text, _hint.text);

    return Scaffold(
      appBar: AppBar(title: const Text('도전 보내기')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, 24),
                children: [
                  Text('$name께 해 볼 만한 일을 보내요', style: t.textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    '하실지는 ${withSubjectParticle(name)} 직접 정해요. "다음에 할게요"를 골라도 따로 알림이 가지 않아요.',
                    style: t.textTheme.bodyMedium?.copyWith(color: k.textSub),
                  ),
                  if (widget.elderId == null && store.links.length >= 2) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final l in store.links)
                          ChoiceChip(
                            label: Text(l.displayName),
                            selected: _elder == l.elderId,
                            onSelected: (_) => setState(() => _elder = l.elderId),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  TextField(
                    key: const Key('challenge_title_field'),
                    controller: _title,
                    maxLength: challengeTitleMax,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: '도전 이름', hintText: '예: 손주 사진을 프로필로 바꿔 보기'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('challenge_hint_field'),
                    controller: _hint,
                    maxLength: challengeHintMax,
                    decoration: const InputDecoration(labelText: '도움말 한 줄 (선택)', hintText: '예: 카톡 → 내 프로필 → 연필 모양'),
                  ),
                  if ((_error ?? problem) != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.block_rounded, size: 18, color: k.dangerText),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              (_error ?? problem)!,
                              key: const Key('challenge_error'),
                              style: t.textTheme.bodySmall?.copyWith(color: k.dangerText, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text('예시에서 고르기', style: t.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in ChallengeTemplate.all)
                        ActionChip(
                          key: ValueKey('example_${e.id}'),
                          label: Text(e.title),
                          onPressed: () => _useExample(e),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('$name 폰에서는 이렇게 보여요', style: t.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  _ElderPreview(
                    from: from.isEmpty ? '가족' : from,
                    title: _title.text.trim().isEmpty ? '도전 이름' : _title.text.trim(),
                    hint: _hint.text.trim(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 18, color: k.textSub),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '돈이나 개인정보가 오가는 일(송금·결제·비밀번호·인증번호 등)은 도전으로 만들 수 없어요. '
                          '해냈는지는 ${withSubjectParticle(name)} 직접 [해냈어요]를 눌러 알려요.',
                          style: t.textTheme.bodySmall?.copyWith(color: k.textSub),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('challenge_send'),
                  onPressed: _sending || _title.text.trim().isEmpty || problem != null ? null : _send,
                  child: Text(_sending ? '보내는 중…' : '$name께 보내기'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 어르신 폰 미리 보기 (고령자 앱 담당에게 제안하는 화면: 큰 글씨, 도전 하나, 버튼 두 개)
class _ElderPreview extends StatelessWidget {
  const _ElderPreview({required this.from, required this.title, required this.hint});
  final String from;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final k = HaebomTokens.of(context);
    return ExcludeSemantics(
      child: Container(
        key: const Key('elder_preview'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        decoration: BoxDecoration(
          color: k.card,
          borderRadius: BorderRadius.circular(Space.cardRadius),
          border: Border.all(color: k.divider, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${withSubjectParticle(from)} 도전을 보냈어요 🌱', style: t.textTheme.bodyLarge?.copyWith(color: k.textSub)),
            const SizedBox(height: 10),
            Text(title, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.3)),
            if (hint.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: k.subtle, borderRadius: BorderRadius.circular(Space.radius)),
                child: Text('💡 $hint', style: t.textTheme.bodyLarge),
              ),
            ],
            const SizedBox(height: 16),
            IgnorePointer(
              child: FilledButton(
                onPressed: () {},
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                child: const Text('해 볼게요', style: TextStyle(fontSize: 20)),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('다음에 할게요', style: t.textTheme.bodyLarge?.copyWith(color: k.textSub)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
