import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let controller = FlutterViewController()
    let frame = self.frame
    self.contentViewController = controller
    self.setFrame(frame, display: true)
    FlutterMethodChannel(name: "launch_at_startup", binaryMessenger: controller.engine.binaryMessenger)
      .setMethodCallHandler { call, result in
        if #available(macOS 13.0, *) {
          switch call.method {
          case "launchAtStartupIsEnabled":
            result(SMAppService.mainApp.status == .enabled)
          case "launchAtStartupSetEnabled":
            let args = call.arguments as? [String: Any]
            do {
              if args?["setEnabledValue"] as? Bool == true {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                  SMAppService.openSystemSettingsLoginItems()
                }
              } else {
                try SMAppService.mainApp.unregister()
              }
              result(nil)
            } catch {
              result(FlutterError(code: "STARTUP", message: error.localizedDescription, details: nil))
            }
          default: result(FlutterMethodNotImplemented)
          }
        } else {
          result(FlutterError(code: "UNSUPPORTED", message: "Login startup requires macOS 13 or later.", details: nil))
        }
      }
    RegisterGeneratedPlugins(registry: controller)
    super.awakeFromNib()
  }
}
