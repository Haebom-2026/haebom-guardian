import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../models/approval_request.dart';
import '../../models/sensitive_app.dart';
import '../../models/sensitivity.dart';
import '../../repositories/guardian_repository.dart';
import '../../repositories/mock_backend.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';
import 'gov24_scenario.dart';

/// 디버그 빌드 전용: 고령자 앱과 서버 없이 보호자 앱을 시험하는 화면.
/// 이 화면의 버튼은 "고령자 앱 + Firebase 서버"가 하는 일을 MockBackend에서 흉내 낸다.
class DeveloperScreen extends StatefulWidget {
  const DeveloperScreen({super.key});

  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<DeveloperScreen> {
  StreamSubscription<void>? _sub;
  late MockBackend _b;
  String _elderId = MockBackend.momId;
  SensitiveApp _app = SensitiveApp.gov24;
  final List<String> _log = [];
  final List<String> _issuedCodes = [];
  Gov24ResidentCopyScenario? _scenario;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub != null) return;
    _b = AppScope.of(context).mockBackend!;
    _sub = _b.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _scenario?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  void _write(String line) {
    if (!mounted) return;
    setState(() => _log.insert(0, '${formatClock(_b.now())}  $line'));
  }

  String _elderLabel(String id) {
    final rel = AppScope.of(context).store.linkFor(id)?.elderLabel;
    return '${rel ?? '미연결'}(${_b.userName(id)})';
  }

  // ---- 시나리오 ----

  Future<void> _startGov24Scenario() async {
    // 10분 중복 방지 규칙 때문에 연달아 실행하면 1단계(정부24 접속) 알림이 생략된다.
    // 서버 규칙은 그대로 두고, 시작 전에 어떻게 진행할지 고르게 한다.
    if (_b.isRecentSensitiveEntry(_elderId, Gov24ResidentCopyScenario.app)) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('정부24 알림이 이미 있어요'),
          content: const Text(
            '10분 안에 같은 가족의 정부24 접속 알림이 있어서, 중복 방지 규칙 때문에 '
            '이번에는 1단계 "정부24 접속" 알림이 생략됩니다(승인 요청과 도움 필요 알림은 갑니다).\n\n'
            '처음부터 모두 보려면 테스트 데이터를 초기화하고 시작하세요.',
          ),
          actions: [
            TextButton(key: const Key('scenario_cancel'), onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            TextButton(
              key: const Key('scenario_start_anyway'),
              onPressed: () => Navigator.pop(ctx, 'anyway'),
              child: const Text('그대로 시작'),
            ),
            FilledButton(
              key: const Key('scenario_reset_start'),
              onPressed: () => Navigator.pop(ctx, 'reset'),
              child: const Text('초기화 후 시작'),
            ),
          ],
        ),
      );
      if (!mounted || choice == null) return;
      if (choice == 'reset') {
        _b.reset();
        setState(() {
          _log.clear();
          _issuedCodes.clear();
        });
        _write('테스트 데이터를 초기화했습니다.');
      }
    }
    final s = Gov24ResidentCopyScenario(backend: _b, elderId: _elderId, log: _write);
    setState(() => _scenario = s);
    _write('▶ 정부24 등본 발급 시나리오 시작 (${_elderLabel(_elderId)})');
    await s.run();
    if (!mounted) return;
    setState(() => _scenario = null);
    _write('■ 정부24 등본 발급 시나리오 종료');
  }

  void _sensitive(ConsentChoice choice) {
    final before = _b.allNotifications.length;
    final (outcome, _) = _b.reportSensitiveEntry(elderId: _elderId, app: _app, choice: choice);
    _write(
      '[${_app.appName} 진입 → ${choice.label}] ${outcome.message} '
      '(전체 알림 $before → ${_b.allNotifications.length})',
    );
  }

  void _requestApproval({String? action}) {
    final a = _b.requestApproval(elderId: _elderId, app: _app, action: action);
    _write(
      a == null
          ? '승인 요청 실패: 연결된 보호자가 없습니다.'
          : '승인 요청 생성: ${_app.appName} · ${ApprovalActions.label(a.action)} (5분 후 만료)',
    );
  }

  void _respondAsSibling(ApprovalRequest a, bool approve) {
    try {
      _b.respond(MockBackend.siblingId, a.id, approve: approve);
      _write('동생이 ${approve ? '승인' : '거절'}함 → 고령자 앱에 전달');
    } on RepositoryException catch (e) {
      _write('동생 응답 거부됨: ${e.code.wire} (${e.userMessage})');
    }
  }

  void _raceTest() {
    final a = _b.requestApproval(elderId: MockBackend.momId, app: SensitiveApp.gov24);
    if (a == null) {
      _write('동시 응답 테스트 실패: 어머니에게 연결된 보호자가 없습니다.');
      return;
    }
    final results = <String>[];
    for (final (gid, approve, name) in [(MockBackend.siblingId, true, '동생'), (MockBackend.meId, false, '나')]) {
      try {
        _b.respond(gid, a.id, approve: approve);
        results.add('$name ${approve ? '승인' : '거절'} ✓ 반영');
      } on RepositoryException catch (e) {
        results.add('$name ${approve ? '승인' : '거절'} ✗ ${e.code.wire}');
      }
    }
    _write('여러 보호자 동시 응답: ${results.join(' / ')} → 최종 ${_b.allApprovals.firstWhere((x) => x.id == a.id).status.label}');
  }

  void _issueCode({bool expired = false}) {
    final code = expired ? _b.issueExpiredConnectCode(_elderId) : _b.issueConnectCode(_elderId);
    setState(() => _issuedCodes.insert(0, code));
    _write('${_elderLabel(_elderId)} 연결 코드 발급: $code${expired ? ' (이미 만료됨)' : ' (10분 유효)'}');
  }

  void _disconnectByElder() {
    final who = _elderLabel(_elderId);
    try {
      _b.disconnectByElder(_elderId, MockBackend.meId);
      _write('$who이(가) 고령자 앱에서 나와의 연결을 해제함');
    } on RepositoryException catch (e) {
      _write('연결 해제 실패: ${e.code.wire} (${e.userMessage})');
    }
    setState(() {});
  }

  Future<void> _reset() async {
    final ok = await confirmDialog(
      context,
      title: '테스트 데이터 초기화',
      message: '모든 알림, 승인, 연결 정보를 초기 데모 상태로 되돌립니다.',
      confirmLabel: '초기화',
      destructive: true,
    );
    if (!ok) return;
    _b.reset();
    setState(() {
      _log.clear();
      _issuedCodes.clear();
    });
    _write('테스트 데이터를 초기화했습니다.');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final pending = _b.allApprovals.where((a) => a.effectiveStatus(_b.now()) == ApprovalStatus.pending).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('개발자 테스트')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '디버그 빌드 전용 화면입니다. 버튼은 고령자 앱과 서버의 동작을 Mock 서버에서 흉내 냅니다. '
                '이 화면에서 만든 알림은 이 기기의 로컬 알림으로만 표시되며, 실제 원격 푸시(FCM)가 아닙니다.',
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onTertiaryContainer),
              ),
            ),
            const SectionHeader('대상 고령자'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _b.elders)
                  ChoiceChip(
                    label: Text(_elderLabel(e.id)),
                    selected: _elderId == e.id,
                    onSelected: (_) => setState(() => _elderId = e.id),
                  ),
              ],
            ),
            const SectionHeader('⓪ 정부24 등본 발급 따라하기 (데모)'),
            Text(
              '고령자가 정부24에서 주민등록표 등본을 발급받는 과정을 4초 간격으로 재현합니다. '
              '① 정부24 접속 알림 → ② 도우미가 메뉴 안내 → ③ 본인 인증 화면에서 고령자가 "보호자에게 묻기" → '
              '도우미 진행 승인 요청 (보호자가 승인하면 계속, 거절·만료되면 중단) → ④ 인증은 고령자가 직접 → '
              '⑤ 45초 멈춤 → 고령자가 "연락할게요" 선택 → 도움 필요 알림 → ⑥ 종료.',
              style: t.textTheme.bodySmall,
            ),
            ListenableBuilder(
              listenable: AppScope.of(context).settings,
              builder: (context, _) {
                final settings = AppScope.of(context).settings;
                return SwitchListTile(
                  key: const Key('scenario_detail_switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('알림에 상세 내용 표시'),
                  subtitle: const Text('설정 화면의 같은 항목과 연동됩니다'),
                  value: settings.showDetailsInNotification,
                  onChanged: (v) => settings.showDetailsInNotification = v,
                );
              },
            ),
            if (_scenario == null)
              FilledButton.icon(
                key: const Key('scenario_start'),
                onPressed: _startGov24Scenario,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('등본 발급 시나리오 시작'),
              )
            else
              OutlinedButton.icon(
                key: const Key('scenario_stop'),
                onPressed: () => _scenario?.cancel(),
                icon: const Icon(Icons.stop_rounded),
                label: const Text('진행 중 · 중단하기'),
              ),
            const SectionHeader('① 민감 앱 진입 (1~7, 12)'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in SensitiveApp.all)
                  ChoiceChip(
                    label: Text(a.category == '은행' && a != SensitiveApp.kakaoBank ? '은행 앱(${a.appName})' : a.appName),
                    selected: _app == a,
                    onSelected: (_) => setState(() => _app = a),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('고령자 팝업: "민감한 개인정보를 사용하는 서비스입니다. 보호자에게 알림을 보내겠습니까?"', style: t.textTheme.bodySmall),
            const SizedBox(height: 8),
            _buttons([
              ('예 선택', () => _sensitive(ConsentChoice.yes)),
              ('아니요 선택', () => _sensitive(ConsentChoice.no)),
              ('팝업 닫기', () => _sensitive(ConsentChoice.dismissed)),
              ('같은 앱 다시 전송(중복)', () => _sensitive(ConsentChoice.yes)),
            ]),
            const SectionHeader('② 승인 요청 (8~11, 13)'),
            _buttons([
              ('승인 요청 생성', _requestApproval),
              ('송금 화면 요청', () => _requestApproval(action: ApprovalActions.moneyMove)),
              ('여러 보호자 동시 응답', _raceTest),
            ]),
            const SizedBox(height: 8),
            if (pending.isEmpty)
              Text('대기 중인 요청 없음', style: t.textTheme.bodySmall)
            else
              for (final a in pending)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_elderLabel(a.elderId)} · ${a.appName} · ${ApprovalActions.label(a.action)}',
                          style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text('남은 시간 ${formatRemaining(a.remaining(_b.now()))}', style: t.textTheme.bodySmall),
                        const SizedBox(height: 8),
                        _buttons([
                          ('상세 열기', () => Navigator.pushNamed(context, AppRoutes.approvalDetail, arguments: a.id)),
                          ('만료시키기', () => _write(_b.forceExpire(a.id) ? '요청을 만료 처리함' : '만료 실패')),
                          ('고령자가 취소', () => _write(_b.cancelApproval(a.id) ? '고령자가 요청을 취소함' : '취소 실패')),
                          if (a.guardianIds.contains(MockBackend.siblingId)) ...[
                            ('동생이 승인', () => _respondAsSibling(a, true)),
                            ('동생이 거절', () => _respondAsSibling(a, false)),
                          ],
                        ], dense: true),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 8),
            Text('고령자 앱 수신 결과 (9)', style: t.textTheme.titleSmall),
            const SizedBox(height: 4),
            if (_b.elderInbox.isEmpty)
              Text('아직 전달된 결과 없음', style: t.textTheme.bodySmall)
            else
              for (final d in _b.elderInbox.take(5))
                Text(
                  '• ${_elderLabel(d.elderId)} ← ${d.status.label} → ${d.elderAppBehavior}'
                  '${d.respondedBy == null ? '' : ' (응답: ${_b.userName(d.respondedBy!)})'}',
                  style: t.textTheme.bodySmall,
                ),
            const SectionHeader('③ 가족 연결 코드 (14, 15)'),
            Text('새 코드를 발급하면 같은 가족의 이전 미사용 코드는 무효화됩니다.', style: t.textTheme.bodySmall),
            const SizedBox(height: 8),
            _buttons([
              ('연결 코드 발급', _issueCode),
              ('만료된 코드 발급', () => _issueCode(expired: true)),
              ('고령자가 나와 연결 해제', _disconnectByElder),
              ('코드 입력 화면', () => Navigator.pushNamed(context, AppRoutes.connectFamily)),
            ]),
            for (final c in _issuedCodes.take(4))
              Builder(
                builder: (context) {
                  final info = _b.codeInfo(c);
                  final state = info == null
                      ? '?'
                      : info.used
                      ? '사용됨'
                      : _b.now().isBefore(info.expiresAt)
                      ? '유효'
                      : '만료';
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('$c · ${_elderLabel(info?.elderId ?? '')} · $state'),
                    trailing: IconButton(
                      tooltip: '복사',
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      onPressed: () => Clipboard.setData(ClipboardData(text: c)),
                    ),
                  );
                },
              ),
            const SectionHeader('④ 보호자별 확인 상태 (16)'),
            for (final n in _b.allNotifications.take(5))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${_elderLabel(n.elderId)} · ${n.appName.isEmpty ? n.type.code : n.appName}'),
                subtitle: Text(
                  n.guardianIds.map((g) => '${_b.userName(g)}: ${n.isReadBy(g) ? '확인함' : '확인 전'}').join('  ·  '),
                ),
                trailing: n.guardianIds.contains(MockBackend.siblingId) && !n.isReadBy(MockBackend.siblingId)
                    ? TextButton(
                        onPressed: () {
                          _b.markRead(MockBackend.siblingId, n.id);
                          _write('동생이 "확인했어요"를 누름 (내 확인 상태는 그대로)');
                        },
                        child: const Text('동생 확인'),
                      )
                    : null,
              ),
            const SectionHeader('⑤ SOS · 도움 필요 (17)'),
            _buttons([
              ('SOS 알림 생성', () => _write(_b.createSos(_elderId) == null ? 'SOS 실패: 연결된 보호자 없음' : 'SOS 알림 생성 (앱 밖)')),
              (
                'SOS (${_app.appName} 사용 중)',
                () => _write(
                  _b.createSos(_elderId, app: _app) == null ? 'SOS 실패: 연결된 보호자 없음' : 'SOS 알림 생성 (${_app.appName} 사용 중)',
                ),
              ),
              (
                '사기 의심 SOS (L3)',
                () => _write(
                  _b.createSos(_elderId, category: SensitivityCategory.scam, reason: '기관 사칭 송금 요청') == null
                      ? 'SOS 실패: 연결된 보호자 없음'
                      : '사기 의심 SOS 생성 (category: scam, level: L3)',
                ),
              ),
              (
                '도움 필요 (고령자 동의)',
                () => _write(
                  _b.createStuck(_elderId, _app) == null ? '실패: 연결된 보호자 없음' : '"가족에게 연락할까요?" → 고령자 "예" → 도움 필요 알림 생성',
                ),
              ),
            ]),
            const SectionHeader('⑥ 초기화 (18)'),
            OutlinedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('테스트 데이터 초기화'),
            ),
            const SectionHeader('실행 기록'),
            if (_log.isEmpty) Text('아직 기록 없음', style: t.textTheme.bodySmall),
            for (final l in _log.take(30))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(l, style: t.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buttons(List<(String, VoidCallback)> items, {bool dense = false}) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final (label, onTap) in items)
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: Size(0, dense ? 36 : 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
          onPressed: onTap,
          child: Text(label),
        ),
    ],
  );
}
