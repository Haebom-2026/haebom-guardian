import 'dart:async';

import '../../models/approval_request.dart';
import '../../models/sensitive_app.dart';
import '../../repositories/mock_backend.dart';

/// 개발자 테스트용 데모: 고령자가 정부24에서 주민등록표 등본을 발급받는 과정을
/// "고령자 앱 + 서버"가 순서대로 처리하는 것처럼 MockBackend에서 재현한다.
///
/// 고령자 앱 실제 흐름(INTEGRATION_REVIEW.md, 2026-11-25)에 맞춘 순서:
/// 1. 정부24 진입 → 동의 팝업 "예" → 이용 알림
/// 2. 도우미가 메뉴 위치 안내 (보호자에게 알림 없음)
/// 3. 본인 인증 화면 → 고령자가 "보호자에게 묻기" 선택 → **승인 요청** → 보호자 응답을 기다림
///    - approved: 안내 계속 / rejected: 안내 중단 / expired: 안내 중단 + SOS 문자 제안 / 중단: 요청 취소
/// 4. 인증은 고령자가 직접 진행 (보호자에게 알림 없음)
/// 5. 발급 신청 화면에서 45초 진행 없음 → "가족에게 연락할까요?" → 고령자 "예" → 도움 필요 알림
///    (도움 필요는 고령자가 동의했을 때만 보낸다, INTEGRATION_REVIEW #10)
/// 6. 고령자가 스스로 발급 완료 → 안내 종료
class Gov24ResidentCopyScenario {
  Gov24ResidentCopyScenario({
    required this.backend,
    required this.elderId,
    required this.log,
    this.stepDelay = const Duration(seconds: 4),
    this.pollInterval = const Duration(milliseconds: 250),
  });

  final MockBackend backend;
  final String elderId;
  final void Function(String line) log;

  /// 단계 사이의 간격
  final Duration stepDelay;

  /// 승인 응답을 기다릴 때 상태를 다시 확인하는 간격
  final Duration pollInterval;

  static const totalSteps = 6;
  static const app = SensitiveApp.gov24;

  bool _cancelled = false;
  bool _running = false;
  String? _pendingApprovalId;

  bool get running => _running;

  /// 시나리오가 만든 승인 요청 (응답 대기 중일 때만)
  String? get pendingApprovalId => _pendingApprovalId;

  void cancel() => _cancelled = true;

  Future<void> run() async {
    if (_running) return;
    _running = true;
    try {
      await _run();
    } finally {
      _running = false;
      _pendingApprovalId = null;
    }
  }

  Future<void> _run() async {
    log('[등본 1/$totalSteps] 고령자가 정부24 앱을 엶 → 동의 팝업에서 "예" 선택 → 보호자에게 이용 알림');
    final (outcome, _) =
        backend.reportSensitiveEntry(elderId: elderId, app: app, choice: ConsentChoice.yes);
    log('    → ${outcome.message}');
    if (outcome == SensitiveEntryOutcome.noGuardians) return _stop('연결된 보호자가 없어 종료');
    if (!await _pause()) return;

    log('[등본 2/$totalSteps] 고령자: "등본 떼는 방법 알려줘" → 해봄 도우미가 메뉴 위치를 안내 (보호자에게 알림 없음)');
    if (!await _pause()) return;

    log('[등본 3/$totalSteps] 본인 인증 화면 → 고령자가 "보호자에게 묻기" 선택 → 보호자에게 도우미 진행 승인 요청');
    final req = backend.requestApproval(elderId: elderId, app: app, action: ApprovalActions.gov24Auth);
    if (req == null) return _stop('연결된 보호자가 없어 종료');
    _pendingApprovalId = req.id;
    log('    → 보호자 응답을 기다리는 중 (최대 ${MockBackend.approvalTtl.inMinutes}분). 보호자 앱에서 승인 또는 거절하세요.');
    final status = await _waitForResponse(req.id);
    _pendingApprovalId = null;
    switch (status) {
      case ApprovalStatus.approved:
        log('    → 보호자가 승인함 → 도우미 안내 계속');
      case ApprovalStatus.rejected:
        return _stop('보호자가 거절함 → 도우미 안내 중단 ("가족이 잠깐 멈추자고 했어요")');
      case ApprovalStatus.expired:
        return _stop('응답 없이 만료됨 → 도우미 안내 중단, 고령자에게 SOS 문자를 보낼지 물음');
      case ApprovalStatus.cancelled:
      case ApprovalStatus.pending:
        return _stop('사용자가 중단함 → 승인 요청 취소');
    }
    if (!await _pause()) return;

    log('[등본 4/$totalSteps] 인증은 고령자가 직접 진행 (보호자에게 알림 없음)');
    if (!await _pause()) return;

    log('[등본 5/$totalSteps] 발급 신청 화면에서 45초 동안 진행 없음 → "가족에게 연락할까요?" → 고령자가 "예" 선택 '
        '→ 보호자에게 도움 필요 알림 (고령자 앱은 문자도 함께 보냄)');
    if (backend.createStuck(elderId, app) == null) return _stop('연결된 보호자가 없어 종료');
    if (!await _pause()) return;

    log('[등본 6/$totalSteps] 고령자가 스스로 발급을 마치고 도우미 안내 종료 '
        '(완료 알림 종류는 통신 규격에 없어 보호자에게 보내지 않음)');
  }

  /// 승인 요청이 종료 상태가 될 때까지 기다린다. 중단하면 요청을 취소한다.
  Future<ApprovalStatus> _waitForResponse(String approvalId) async {
    while (true) {
      final a = backend.allApprovals.firstWhere((x) => x.id == approvalId);
      final status = a.effectiveStatus(backend.now());
      if (status.isFinal) {
        if (status == ApprovalStatus.expired) backend.expireOverdue();
        return status;
      }
      if (_cancelled) {
        backend.cancelApproval(approvalId);
        return ApprovalStatus.cancelled;
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  void _stop(String reason) => log('    → 시나리오 중단: $reason');

  Future<bool> _pause() async {
    if (_cancelled) {
      _stop('사용자가 중단함');
      return false;
    }
    await Future<void>.delayed(stepDelay);
    if (_cancelled) _stop('사용자가 중단함');
    return !_cancelled;
  }
}
