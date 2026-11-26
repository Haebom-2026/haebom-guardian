import 'package:material_ui/material_ui.dart';

import '../app/dependencies.dart';
import '../models/approval_request.dart';
import '../repositories/guardian_repository.dart';
import 'common.dart';

/// 승인 응답: 확인 창 → 서버(또는 Mock)에 응답 → 결과 안내.
///
/// 상세 화면과 홈의 "지금 확인할 것" 카드가 같은 흐름을 쓴다 (확인 창 없이 바로 응답하지 않는다).
/// 내부 값은 그대로: 계속해도 돼요 = approved, 잠깐 멈춰요 = rejected.
/// [onBusy]: 확인 창을 닫고 실제로 보내는 동안 true, 끝나면 false (버튼 비활성·로딩 표시용).
/// 응답을 보냈으면 true. 취소했거나 실패하면 false.
Future<bool> respondWithConfirm(
  BuildContext context,
  ApprovalRequest a, {
  required bool approve,
  void Function(bool busy)? onBusy,
}) async {
  final deps = AppScope.of(context);
  final who = deps.store.nameOf(a.elderId);
  final ok = await confirmDialog(
    context,
    title: approve ? '도우미 안내를 계속해도 될까요?' : '도우미 안내를 잠깐 멈출까요?',
    message: approve
        ? '$who의 해봄 도우미가 \'${ApprovalActions.label(a.action)}\'을(를) 계속합니다.\n'
            '실제 금융 거래나 본인인증을 대신 승인하는 것은 아닙니다.'
        : '$who의 해봄 도우미가 안내를 멈추고 "가족이 잠깐 멈추자고 했어요"라고 알려 드립니다.\n'
            '필요하면 직접 전화해 상황을 확인해 주세요.',
    confirmLabel: approve ? '계속해도 돼요' : '잠깐 멈춰요',
    destructive: !approve,
  );
  if (!ok || !context.mounted) return false;
  onBusy?.call(true);
  try {
    await deps.repository.respondToApproval(a.id, approve: approve);
    if (context.mounted) {
      showMessage(context,
          approve ? '"계속해도 돼요"를 보냈습니다. 가족의 해봄 앱에 바로 전달됩니다.' : '"잠깐 멈춰요"를 보냈습니다. 가족의 해봄 앱에 바로 전달됩니다.');
    }
    return true;
  } on RepositoryException catch (e) {
    if (context.mounted) showMessage(context, e.userMessage);
  } catch (_) {
    if (context.mounted) showMessage(context, '처리하지 못했습니다. 네트워크 연결을 확인해 주세요.');
  } finally {
    onBusy?.call(false);
  }
  return false;
}
