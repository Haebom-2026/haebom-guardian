import 'package:material_ui/material_ui.dart';

import '../../app/dependencies.dart';
import '../../app/theme.dart';
import '../../models/approval_request.dart';
import '../../models/sensitivity.dart';
import '../../repositories/guardian_repository.dart';
import '../../utils/formatters.dart';
import '../../widgets/approval_actions.dart';
import '../../widgets/common.dart';

class ApprovalDetailScreen extends StatefulWidget {
  const ApprovalDetailScreen({super.key, required this.approvalId});
  final String approvalId;

  @override
  State<ApprovalDetailScreen> createState() => _ApprovalDetailScreenState();
}

class _ApprovalDetailScreenState extends State<ApprovalDetailScreen> {
  Future<ApprovalRequest>? _future;
  bool _submitting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).repository.getApproval(widget.approvalId);
  }

  Future<void> _respond(ApprovalRequest a, bool approve) async {
    if (_submitting) return; // 중복 탭 방지
    await respondWithConfirm(context, a, approve: approve, onBusy: (busy) {
      if (mounted) setState(() => _submitting = busy);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    return Scaffold(
      appBar: AppBar(title: const Text('승인 요청 상세')),
      body: SafeArea(
        top: false,
        child: FutureBuilder<ApprovalRequest>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              final e = snap.error;
              return ListView(children: [
                EmptyState(
                  icon: Icons.search_off_rounded,
                  title: '요청을 열 수 없습니다',
                  message: e is RepositoryException ? e.userMessage : '잠시 후 다시 시도해 주세요.',
                ),
              ]);
            }
            // 다른 보호자의 응답·취소·만료가 실시간 반영되도록 저장소 스트림의 최신 값을 사용
            return ListenableBuilder(
              listenable: store,
              builder: (context, _) {
                final live = store.approvals.where((x) => x.id == widget.approvalId);
                final a = live.isNotEmpty ? live.first : snap.data!;
                return CountdownBuilder(builder: (context) => _body(context, a));
              },
            );
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, ApprovalRequest a) {
    final store = AppScope.of(context).store;
    final t = Theme.of(context);
    final k = HaebomTokens.of(context);
    final now = store.now();
    final status = a.effectiveStatus(now);
    final who = store.nameOf(a.elderId);
    final pending = status == ApprovalStatus.pending;
    final style = StatusStyle.of(status, t.brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.page + 4, 8, Space.page + 4, Space.page),
            children: [
              // 위: 상태 꼬리표 + 요청 문장
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: style.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
                    child: StatusBadge(status),
                  ),
                  Text('도우미 진행 승인', style: t.textTheme.bodyMedium?.copyWith(color: k.textSub, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 14),
              Text(approvalMessage(a, who), style: t.textTheme.titleLarge?.copyWith(fontSize: 21, height: 1.45)),
              const SizedBox(height: 20),
              // 남은 시간(대기 중) 또는 결과 안내
              if (pending) _Countdown(remaining: a.remaining(now), total: a.expiresAt.difference(a.createdAt)) else _statusNotice(context, a, status),
              const SizedBox(height: 16),
              _row(context, '요청자', '$who (${store.linkFor(a.elderId)?.elderName ?? '-'})'),
              _row(context, '서비스', a.appName),
              _row(context, '요청 내용', ApprovalActions.label(a.action)),
              if (a.category != null && a.category != SensitivityCategory.none) _row(context, '분류', a.category!.label),
              _row(context, '요청 시간', formatDateTime(a.createdAt, now)),
              if (!pending && a.respondedAt != null && status != ApprovalStatus.expired)
                _row(context, '처리 시간', formatDateTime(a.respondedAt!, now)),
              if (a.respondedBy != null) _row(context, '응답한 보호자', a.respondedBy == store.guardianId ? '나' : '다른 보호자'),
            ],
          ),
        ),
        // 아래 고정: 안내 문구 + 응답 버튼
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, Space.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '해봄은 실제 은행 거래나 본인인증을 승인·차단하지 않습니다. '
                '이 승인은 해봄 도우미가 안내를 계속해도 되는지에 대한 가족의 확인입니다.',
                style: t.textTheme.bodySmall?.copyWith(fontSize: 13),
              ),
              if (pending) ...[
                const SizedBox(height: 12),
                // 내부 값은 그대로: 계속해도 돼요 = approved, 잠깐 멈춰요 = rejected (INTEGRATION_REVIEW #7)
                FilledButton.icon(
                  key: const Key('approve_button'),
                  onPressed: _submitting ? null : () => _respond(a, true),
                  icon: _submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow_rounded),
                  label: const Text('계속해도 돼요'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  key: const Key('reject_button'),
                  style: FilledButton.styleFrom(backgroundColor: k.subtle, foregroundColor: k.text),
                  onPressed: _submitting ? null : () => _respond(a, false),
                  icon: const Icon(Icons.pan_tool_outlined),
                  label: const Text('잠깐 멈춰요'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusNotice(BuildContext context, ApprovalRequest a, ApprovalStatus status) {
    final t = Theme.of(context);
    final style = StatusStyle.of(status, t.brightness);
    final who = AppScope.of(context).store.nameOf(a.elderId);
    final text = switch (status) {
      ApprovalStatus.approved => '"계속해도 돼요"로 응답해 해봄 도우미가 안내를 계속했습니다.',
      ApprovalStatus.rejected => '"잠깐 멈춰요"로 응답해 해봄 도우미가 안내를 멈췄습니다.',
      ApprovalStatus.expired => '응답 시간(5분)이 지나 해봄 도우미가 안내를 멈췄습니다. '
          '${withSubjectParticle(who)} 도움이 필요할 수 있으니 연락해 보세요.',
      ApprovalStatus.cancelled => '${withSubjectParticle(who)} 요청을 취소했습니다. 더 이상 응답하지 않아도 됩니다.',
      ApprovalStatus.pending => '',
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: style.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Space.cardRadius - 2)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(style.icon, color: style.color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: t.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value, {Color? color, bool bold = false}) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(label, style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                style: t.textTheme.bodyLarge?.copyWith(color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// 응답 남은 시간: 큰 숫자 + 줄어드는 막대 (주의 색 + 글자로 표시)
class _Countdown extends StatelessWidget {
  const _Countdown({required this.remaining, required this.total});
  final Duration remaining;
  final Duration total;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final k = HaebomTokens.of(context);
    final ratio = total.inMilliseconds <= 0 ? 0.0 : (remaining.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: k.cautionBg, borderRadius: BorderRadius.circular(Space.cardRadius - 2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text('남은 시간', style: t.textTheme.bodyLarge?.copyWith(color: k.cautionText, fontWeight: FontWeight.w700)),
              Text(
                formatRemaining(remaining),
                style: t.textTheme.headlineSmall?.copyWith(
                  fontSize: 30,
                  color: k.cautionText,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              color: k.cautionText,
              backgroundColor: k.cautionText.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}
