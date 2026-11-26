import 'package:guardian_app/models/family_link.dart';
import 'package:guardian_app/repositories/guardian_repository.dart';
import 'package:guardian_app/repositories/server/guardian_server_api.dart';

/// 서버 API 호출을 기록하는 가짜 구현
class FakeServerApi implements GuardianServerApi {
  final calls = <String>[];
  RepositoryException? failWith;
  void Function()? onRespond;

  void _call(String c) {
    calls.add(c);
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> ensureGuardianProfile({String? name}) async => _call('profile');
  @override
  Future<void> respondApproval(String approvalId, {required bool approve}) async {
    _call('respond:$approvalId:$approve');
    onRespond?.call();
  }

  @override
  Future<FamilyLink> connectWithCode(String code, {required String elderLabel, String guardianLabel = ''}) async {
    _call('connect:$code');
    return FamilyLink(
        elderId: 'elder_x', guardianId: '', elderName: '박말순', elderLabel: elderLabel, guardianLabel: guardianLabel, connectedAt: DateTime(2026));
  }

  @override
  Future<void> disconnect(String elderId) async => _call('disconnect:$elderId');
  @override
  Future<void> registerDevice({required String deviceId, required String fcmToken, required String platform}) async =>
      _call('register:$deviceId:$fcmToken:$platform');
  @override
  Future<void> unregisterDevice(String deviceId) async => _call('unregister:$deviceId');
}

