// 실제 Firestore SDK + Firebase 로컬 에뮬레이터로 "서버 모드"를 기기에서 검증한다.
//
//   (tool/firebase_emulator에서 에뮬레이터 실행 후)
//   flutter test integration_test/server_emulator_test.dart -d <기기> --dart-define=FIREBASE_EMULATOR_HOST=<주소>
//   주소: iOS 시뮬레이터 localhost / Android 에뮬레이터 10.0.2.2 / 실제 기기 맥 Wi-Fi IP
//
// - 공유 Firebase 프로젝트·서버를 쓰지 않는다 (프로젝트 ID demo-haebom).
// - 고령자 앱·공통 서버가 쓰는 문서는 테스트가 Firestore에 직접 써서 흉내 낸다.
// - 승인·연결 API는 서버 규칙을 흉내 내는 테스트용 구현(_EmulatorServerApi)으로 대신한다.
// - 실제 로컬 알림 플러그인으로 알림을 표시한다. OS 알림을 손가락으로 누르는 동작은 자동화할 수 없어,
//   플러그인 탭 콜백과 같은 경로(AppRoutes.openTarget)로 상세 이동을 검증한다.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/app/app.dart';
import 'package:guardian_app/app/dependencies.dart';
import 'package:guardian_app/app/routes.dart';
import 'package:guardian_app/models/family_link.dart';
import 'package:guardian_app/repositories/guardian_repository.dart';
import 'package:guardian_app/repositories/server/guardian_server_api.dart';
import 'package:guardian_app/repositories/server/server_repository.dart';
import 'package:guardian_app/services/notification_service.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart' show ScaffoldMessenger, ScaffoldMessengerState, Scrollable;

const _host = String.fromEnvironment('FIREBASE_EMULATOR_HOST');

/// 실제 플러그인으로 알림을 띄우면서 호출 내용을 기록한다
class _RecordingNotifier implements LocalNotifier {
  final _inner = PluginLocalNotifier();
  final shown = <LocalAlert>[];
  late void Function(AlertTarget) onTap;

  @override
  Future<void> initialize(void Function(AlertTarget target) onTap) {
    this.onTap = onTap;
    return _inner.initialize(onTap);
  }

  @override
  Future<bool> requestPermission() async => true; // 권한 팝업이 테스트를 멈추지 않도록
  @override
  Future<void> show(LocalAlert alert) {
    shown.add(alert);
    return _inner.show(alert);
  }

  @override
  Future<AlertTarget?> launchTarget() async => null;
}

/// 공통 서버의 규칙(먼저 온 응답만, 코드 검증, links 생성)을 흉내 내는 테스트용 서버 API
class _EmulatorServerApi implements GuardianServerApi {
  _EmulatorServerApi(this.db, this.me);
  final FirebaseFirestore db;
  final String me;

  @override
  Future<void> ensureGuardianProfile({String? name}) async {}

  // 에뮬레이터 검증은 Firestore 방식이라 #21·#22는 쓰지 않는다
  @override
  Future<NotificationPage> fetchNotifications({int limit = 50, String? cursor, String? since}) async =>
      const NotificationPage(items: []);

  @override
  Future<void> markNotificationRead(String notificationId) async {}

  @override
  Future<List<FamilyLink>> fetchLinks() async {
    final snap = await db.collection('links').where('guardianId', isEqualTo: me).get();
    return snap.docs.map((d) => FirestoreMappers.link(d.data())).toList();
  }

  @override
  Future<void> respondApproval(String approvalId, {required bool approve}) =>
      db.runTransaction((tx) async {
        final ref = db.doc('approvals/$approvalId');
        final d = (await tx.get(ref)).data()!;
        if (d['status'] != 'pending') throw const RepositoryException(RepositoryErrorCode.alreadyResponded);
        tx.update(ref, {
          'status': approve ? 'approved' : 'rejected',
          'respondedBy': me,
          'respondedAt': FieldValue.serverTimestamp(),
        });
      });

  @override
  Future<FamilyLink> connectWithCode(String code, {required String elderLabel, String guardianLabel = ''}) async {
    final codeRef = db.doc('connectCodes/$code');
    final c = (await codeRef.get()).data();
    if (c == null) throw const RepositoryException(RepositoryErrorCode.invalidCode);
    if (c['used'] == true) throw const RepositoryException(RepositoryErrorCode.codeUsed);
    final elderId = c['elderId'] as String;
    final link = {
      'elderId': elderId,
      'guardianId': me,
      'elderName': c['elderName'],
      'elderLabel': elderLabel,
      'guardianLabel': guardianLabel,
      'connectedAt': Timestamp.now(),
    };
    await db.doc('links/${elderId}_$me').set(link);
    await codeRef.update({'used': true});
    return FirestoreMappers.link(link);
  }

  @override
  Future<void> disconnect(String elderId) => db.doc('links/${elderId}_$me').delete();
  @override
  Future<void> registerDevice({required String deviceId, required String fcmToken, required String platform}) async {}
  @override
  Future<void> unregisterDevice(String deviceId) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('서버 모드(Firestore 에뮬레이터): 실시간 수신 → 로컬 알림 → 상세 → 확인·승인·연결', (tester) async {
    if (_host.isEmpty) {
      markTestSkipped('FIREBASE_EMULATOR_HOST가 없어 건너뜀');
      return;
    }
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: 'AIzaDemoKeyForLocalFirebaseEmulator0000',
        appId: ios ? '1:000000000000:ios:0000000000000000' : '1:000000000000:android:0000000000000000',
        messagingSenderId: '000000000000',
        projectId: 'demo-haebom',
        iosBundleId: ios ? 'com.yju.haebom.guardianApp' : null,
      ),
    );
    final db = FirebaseFirestore.instance;
    db.useFirestoreEmulator(_host, 8080, automaticHostMapping: false);
    db.settings = const Settings(persistenceEnabled: false);

    // 실행마다 다른 사용자 ID (이전 실행 데이터와 섞이지 않게)
    final run = DateTime.now().millisecondsSinceEpoch;
    final me = 'guardian_$run';
    final mom = 'elder_mom_$run';
    final grandma = 'elder_grandma_$run';

    Future<void> wait(bool Function() done, {String what = '', int seconds = 15}) async {
      for (var i = 0; i < seconds * 10; i++) {
        if (done()) return;
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      fail('시간 초과: $what');
    }

    // 고령자 앱·서버가 쓴 것처럼 문서 생성
    await tester.runAsync(() => db.doc('links/${mom}_$me').set({
          'elderId': mom,
          'guardianId': me,
          'elderName': '김순자',
          'relationship': '어머니',
          'connectedAt': Timestamp.now(),
        }));

    final notifier = _RecordingNotifier();
    final deps = AppDependencies(
      repository: ServerGuardianRepository(firestore: db, guardianId: me, api: _EmulatorServerApi(db, me)),
      notifier: notifier,
    );
    await notifier.initialize((t) => AppRoutes.openTarget(deps.navigatorKey.currentState, t));
    deps.notifications.start();
    await tester.pumpWidget(HaebomFamilyApp(deps: deps));
    await wait(() => find.textContaining('연결된 가족 1명').evaluate().isNotEmpty, what: 'links 실시간 수신');

    Future<String> addNotification(String type, {String app = '정부24', String pkg = 'kr.go.minwon.m'}) async {
      final ref = await tester.runAsync(() => db.collection('notifications').add({
            'elderId': mom,
            'guardianIds': [me, 'guardian_other'],
            'appName': app,
            'packageName': pkg,
            'type': type,
            'createdAt': FieldValue.serverTimestamp(),
            'readBy': <String, Object>{},
          }));
      return ref!.id;
    }

    LocalAlert alertFor(String id) => notifier.shown.firstWhere((a) => a.id == NotificationService.idFor(id));
    bool alerted(String id) => notifier.shown.any((a) => a.id == NotificationService.idFor(id));

    // 1) 일반 알림: 실시간 수신 → 로컬 알림(잠금 화면 최소 문구) → 목록 표시
    final entry = await addNotification('sensitive_entry');
    await wait(() => alerted(entry), what: '일반 알림 로컬 알림');
    expect(alertFor(entry).body, '새 가족 알림이 도착했습니다.');
    expect(alertFor(entry).channel, AlertChannel.activity);
    await wait(() => find.text('어머니가 정부24를 사용하려고 합니다.').evaluate().isNotEmpty, what: '홈 목록 반영');

    // 2) 도움 필요 / SOS (사용 중인 앱 포함)
    final stuck = await addNotification('stuck');
    final sos = await addNotification('sos');
    await wait(() => alerted(stuck) && alerted(sos), what: '도움 필요·SOS 알림');
    expect(alertFor(stuck).body, '가족에게 도움이 필요할 수 있습니다. 앱에서 확인해 주세요.');
    expect(alertFor(sos).channel, AlertChannel.sos);
    expect(alertFor(sos).title, '해봄 가족 · 긴급');

    // 3) 중복 방지: 같은 문서의 FCM 포그라운드 메시지·문서 수정이 와도 다시 띄우지 않음
    final before = notifier.shown.length;
    deps.notifications.showRemote(AlertTarget(AlertTarget.notification, entry), type: 'sensitive_entry');
    await tester.runAsync(() => db.doc('notifications/$sos').update({'readBy.guardian_other': Timestamp.now()}));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    expect(notifier.shown.length, before, reason: '같은 문서는 한 번만 표시');

    // 4) 알림 탭 → 상세 → "확인했어요" → 에뮬레이터에 readBy 기록 (내 항목만)
    notifier.onTap(alertFor(sos).target!);
    await wait(() => find.text('알림 상세').evaluate().isNotEmpty, what: '상세 이동');
    expect(find.text('어머니가 정부24 사용 중 SOS 도움 요청을 보냈습니다.'), findsWidgets); // 상세 + 뒤의 홈 목록
    await tester.tap(find.byKey(const Key('notification_confirm')));
    await wait(() => find.byKey(const Key('notification_confirmed')).evaluate().isNotEmpty, what: '확인 반영');
    final readBy = (await tester.runAsync(() => db.doc('notifications/$sos').get()))!.data()!['readBy'] as Map;
    expect(readBy.keys, containsAll([me, 'guardian_other']));
    deps.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    // 5) 승인 요청 → 알림 → 탭 → "계속해도 돼요" → approved
    final approval = await tester.runAsync(() => db.collection('approvals').add({
          'elderId': mom,
          'guardianIds': [me],
          'appName': '정부24',
          'packageName': 'kr.go.minwon.m',
          'action': 'guide_gov24_auth',
          'status': 'pending',
          'createdAt': Timestamp.now(),
          'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 5))),
          'respondedAt': null,
          'respondedBy': null,
        }));
    await wait(() => alerted(approval!.id), what: '승인 요청 알림');
    expect(alertFor(approval!.id).channel, AlertChannel.approval);
    notifier.onTap(alertFor(approval.id).target!);
    await wait(() => find.byKey(const Key('approve_button')).evaluate().isNotEmpty, what: '승인 상세');
    await tester.tap(find.byKey(const Key('approve_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_dialog_ok')));
    await wait(() => find.byKey(const Key('approve_button')).evaluate().isEmpty, what: '승인 처리');
    final status = (await tester.runAsync(() => db.doc('approvals/${approval.id}').get()))!.data()!['status'];
    expect(status, 'approved');
    deps.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    // 6) 가족 연결: 고령자 앱이 발급한 코드(서버 문서) 입력 → links 생성 → 실시간 반영
    await tester.runAsync(() => db.doc('connectCodes/${run % 900000 + 100000}').set({
          'elderId': grandma,
          'elderName': '박말순',
          'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 10))),
          'used': false,
        }));
    // 5단계의 안내(SnackBar)가 아래 버튼을 가리지 않도록 지운다
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).clearSnackBars();
    deps.navigatorKey.currentState!.pushNamed(AppRoutes.connectFamily);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('connect_code_field')), '${run % 900000 + 100000}');
    // 화면이 좁거나(접힌 폴드·키보드) 목록 아래쪽 항목이 아직 만들어지지 않았을 수 있어 보일 때까지 스크롤한다
    final list = find.byType(Scrollable).first;
    Future<void> tapInList(Finder f) async {
      await tester.scrollUntilVisible(f, 150, scrollable: list);
      await tester.pump();
      await tester.tap(f);
      await tester.pump();
    }

    await tapInList(find.text('할머니'));
    await tapInList(find.byKey(const Key('guardian_label_손녀')));
    await tapInList(find.byKey(const Key('connect_submit')));
    await wait(() => deps.store.links.length == 2, what: '가족 연결 반영');

    // 7) 고령자 쪽 연결 해제(서버가 links 삭제) → 그 가족 알림이 목록에서 사라짐
    await tester.runAsync(() => db.doc('links/${mom}_$me').delete());
    await wait(() => deps.store.notifications.isEmpty && deps.store.links.length == 1, what: '해제 반영');

    deps.dispose();
  });
}
