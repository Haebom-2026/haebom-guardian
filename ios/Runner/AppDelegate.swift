import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 앱 실행 중(포그라운드)에도 로컬 알림을 표시하고 탭 이벤트를 받기 위해 필요
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // 알림 권한을 앱에서 더 물어볼 수 없을 때 설정 앱의 이 앱 알림 화면을 연다
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HaebomSettings") else { return }
    FlutterMethodChannel(name: "haebom/settings", binaryMessenger: registrar.messenger())
      .setMethodCallHandler { call, result in
        guard call.method == "openNotificationSettings" else { return result(FlutterMethodNotImplemented) }
        let target: String
        if #available(iOS 16.0, *) {
          target = UIApplication.openNotificationSettingsURLString
        } else {
          target = UIApplication.openSettingsURLString
        }
        if let url = URL(string: target) { UIApplication.shared.open(url) }
        result(nil)
      }
  }
}
