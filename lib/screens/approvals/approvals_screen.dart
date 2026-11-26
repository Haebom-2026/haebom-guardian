import 'package:material_ui/material_ui.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../models/approval_request.dart';
import '../../models/sensitivity.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';

/// 도우미 진행 승인: 맨 위 "응답이 필요한 요청"(주황 상자, 남은 시간 · 요청 확인하기),
/// 아래 "지난 요청" 흰 카드(승인 완료·거절·응답 시간 지남·요청 취소됨, 아이콘 + 글자). 응답은 상세 화면에서 한다.
class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    final t = Theme.of(context);
    final k = HaebomTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('도우미 진행 승인')),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) => CountdownBuilder(builder: (context) {
            final now = store.now();
            final all = store.approvalsFor(elderId: store.selectedElderId);
            final pending = all.where((a) => a.effectiveStatus(now) == ApprovalStatus.pending).toList();
            final past = all.where((a) => a.effectiveStatus(now) != ApprovalStatus.pending).toList();
            void open(ApprovalRequest a) => Navigator.pushNamed(context, AppRoutes.approvalDetail, arguments: a.id);
            return ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, 0),
                  child: Text('가족의 해봄 도우미가 안내를 계속해도 되는지 묻는 요청입니다.', style: t.textTheme.bodySmall),
                ),
                if (store.links.length >= 2) ...[
                  const SizedBox(height: 12),
                  FamilyFilterBar(store: store),
                ],
                SectionHeader('응답이 필요한 요청', count: pending.length, countKey: const ValueKey('pending_count')),
                if (pending.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.page),
                    child: Text('지금 응답할 요청이 없어요.', style: t.textTheme.bodySmall),
                  )
                else
                  for (final a in pending)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.page - 4, 0, Space.page - 4, Space.gap),
                      child: HelpCard(
                        key: ValueKey('pending_${a.id}'),
                        tone: RiskTone.caution,
                        icon: Icons.hourglass_top_rounded,
                        tag: '승인 대기 · ${formatRemaining(a.remaining(now))} 남음',
                        title: '${store.nameOf(a.elderId)} · ${a.appName}',
                        lines: [Text(ApprovalActions.label(a.action), style: t.textTheme.bodyLarge?.copyWith(color: k.text))],
                        buttonLabel: '요청 확인하기',
                        buttonKey: ValueKey('pending_open_${a.id}'),
                        onPressed: () => open(a),
                      ),
                    ),
                // 과거 처리 기록은 별도 섹션의 흰 카드로 현재 요청과 분리
                const SizedBox(height: 8),
                SectionHeader('지난 요청', count: past.isEmpty ? null : past.length),
                if (past.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.page),
                    child: Text('지난 승인 요청이 없습니다.', style: t.textTheme.bodySmall),
                  )
                else
                  CardGroup(children: [
                    for (final (i, a) in past.indexed) ...[
                      if (i > 0) const RowDivider(),
                      ApprovalCard(request: a, store: store, onTap: () => open(a)),
                    ],
                  ]),
              ],
            );
          }),
        ),
      ),
    );
  }
}
