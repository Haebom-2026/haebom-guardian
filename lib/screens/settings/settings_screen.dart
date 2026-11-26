import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../services/push_service.dart';
import '../../widgets/common.dart';

/// pubspec.yaml의 version과 맞춰 관리한다.
const appVersion = '0.1.0 (1)';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    final settings = deps.settings;
    const divider = Divider(indent: Space.page, endIndent: Space.page);
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: settings,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const _GroupLabel('알림 받기', first: true),
              CardGroup(children: [
                SwitchListTile(
                  title: const Text('SOS 알림'),
                  subtitle: const Text('SOS · 사기 의심 (끄지 않는 것을 권장)'),
                  value: settings.sosAlerts,
                  onChanged: (v) => settings.sosAlerts = v,
                ),
                divider,
                SwitchListTile(
                  title: const Text('승인 요청 알림'),
                  subtitle: const Text('도우미 진행 승인 요청'),
                  value: settings.approvalAlerts,
                  onChanged: (v) => settings.approvalAlerts = v,
                ),
                divider,
                SwitchListTile(
                  title: const Text('앱 이용 알림'),
                  subtitle: const Text('민감 서비스 이용 · 도움 필요'),
                  value: settings.activityAlerts,
                  onChanged: (v) => settings.activityAlerts = v,
                ),
              ]),
              const _GroupLabel('잠금 화면'),
              CardGroup(children: [
                SwitchListTile(
                  title: const Text('간략하게 보기'),
                  subtitle: const Text('켜면 누가 어떤 앱을 썼는지 빼고 "새 가족 알림이 도착했습니다"만 표시. '
                      '잠금 화면에서는 휴대폰 설정에 따라 내용이 숨겨집니다'),
                  value: settings.briefNotifications,
                  onChanged: (v) => settings.briefNotifications = v,
                ),
                divider,
                ListTile(
                  title: const Text('기기 알림 권한 확인'),
                  subtitle: const Text('알림이 오지 않을 때 눌러 주세요'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final granted = await deps.notifications.requestPermission();
                    if (context.mounted) {
                      showMessage(context, granted ? '알림 권한이 허용되어 있습니다.' : '알림 권한이 꺼져 있습니다. 휴대폰 설정에서 허용해 주세요.');
                    }
                  },
                ),
              ]),
              const _GroupLabel('연결 상태'),
              CardGroup(children: [
                ListTile(
                  title: const Text('데이터 연결'),
                  trailing: Text(deps.mockBackend != null ? '테스트 데이터' : '서버'),
                ),
                if (deps.push != null) ...[
                  divider,
                  _PushStatusTile(push: deps.push!),
                ],
              ]),
              const _GroupLabel('정보'),
              CardGroup(children: [
                ListTile(
                  title: const Text('개인정보 보호 안내'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showPrivacy(context),
                ),
                divider,
                const ListTile(
                  leading: BrandMark(size: 32),
                  title: Text('해봄 가족'),
                  subtitle: Text('오늘도, 스스로 해봄.'),
                  trailing: Text(appVersion),
                ),
                divider,
                ListTile(
                  title: const Text('오픈소스 라이선스'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: '해봄 가족',
                    applicationVersion: appVersion,
                  ),
                ),
              ]),
              if (AppRoutes.developerEnabled && deps.mockBackend != null) ...[
                const _GroupLabel('개발자'),
                CardGroup(children: [
                  ListTile(
                    key: const Key('developer_entry'),
                    title: const Text('개발자 테스트 모드'),
                    subtitle: const Text('디버그 빌드에서만 표시'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pushNamed(context, AppRoutes.developer),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showPrivacy(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('개인정보 보호 안내', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              for (final line in const [
                '가족이 "보호자에게 알림 보내기"에 직접 동의한 경우에만 앱 이용 사실이 전달됩니다.',
                '해봄은 어떤 앱을 이용했는지와 시간만 전달하며, 화면 내용이나 입력한 정보는 알 수 없습니다.',
                '비밀번호, 계좌번호, 주민등록번호, 금융 거래 내용은 수집하지 않습니다.',
                '다른 앱의 화면을 캡처하거나 저장·전송하지 않습니다.',
                '가족의 위치나 실시간 접속 상태는 수집하지 않습니다.',
                '연결된 보호자만 해당 가족의 알림과 승인 요청을 볼 수 있습니다.',
                '승인은 해봄 도우미의 안내를 계속할지에 대한 확인이며, 실제 금융 거래나 본인인증을 승인하지 않습니다.',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.check_rounded, size: 18)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(line)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 원격 푸시(FCM) 수신 상태. 받을 수 없는 경우에는 앱이 켜져 있을 때만 알림이 온다는 점을 알려 준다.
class _PushStatusTile extends StatelessWidget {
  const _PushStatusTile({required this.push});
  final PushService push;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: push,
        builder: (context, _) {
          final (label, detail) = switch (push.state) {
            PushState.active => ('사용 중', '앱을 닫아도 알림을 받습니다.'),
            PushState.idle => ('확인 중', null),
            PushState.permissionDenied => ('알림 권한 꺼짐', '휴대폰 설정에서 해봄 가족 알림을 허용해 주세요.'),
            PushState.noToken => ('사용할 수 없음', '이 기기에서는 앱이 켜져 있을 때만 알림을 받습니다.'),
            PushState.registerFailed => ('서버 연결 대기', '서버에 연결되면 자동으로 다시 시도합니다. 그동안은 앱이 켜져 있을 때만 알림을 받습니다.'),
          };
          final token = push.token;
          return ListTile(
            key: const Key('push_status'),
            title: const Text('원격 알림'),
            subtitle: (detail == null && !(kDebugMode && token != null))
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (detail != null) Text(detail),
                      // Firebase 콘솔 "테스트 메시지 전송"에 붙여 넣을 토큰 (디버그 빌드에서만)
                      if (kDebugMode && token != null)
                        TextButton.icon(
                          key: const Key('copy_fcm_token'),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: token));
                            ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(content: Text('FCM 토큰을 복사했습니다 (테스트용)')));
                          },
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text('FCM 토큰 복사 (테스트용)'),
                        ),
                    ],
                  ),
            trailing: push.state == PushState.registerFailed
                ? TextButton(onPressed: push.retry, child: Text(label))
                : Text(label),
          );
        },
      );
}

/// 설정 묶음 제목 (작은 회색 글자)
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text, {this.first = false});
  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(Space.page + 4, first ? 8 : Space.section, Space.page, 8),
        child: Semantics(
          header: true,
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: HaebomTokens.of(context).textSub,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      );
}
