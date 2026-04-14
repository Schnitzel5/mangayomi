import UIKit
import Flutter
import Libmtorrentserver
import app_links
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let backgroundLibraryUpdateTaskId =
    "com.kodjodevf.mangayomi.background_library_update"
  private var activeBackgroundTasks: [String: UIBackgroundTaskIdentifier] = [:]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
      WorkmanagerPlugin.registerPeriodicTask(
          withIdentifier: backgroundLibraryUpdateTaskId,
          frequency: NSNumber(value: 15 * 60)
      )

      let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
      let mChannel = FlutterMethodChannel(name: "com.kodjodevf.mangayomi.libmtorrentserver", binaryMessenger: controller.binaryMessenger)
              mChannel.setMethodCallHandler({
                  (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
                  switch call.method {
                  case "start":
                      let args = call.arguments as? Dictionary<String, Any>
                      let config = args?["config"] as? String
                      var error: NSError?
                      let mPort = UnsafeMutablePointer<Int>.allocate(capacity: MemoryLayout<Int>.stride)
                      if LibmtorrentserverStart(config, mPort, &error){
                          result(mPort.pointee)
                      }else{
                          result(FlutterError(code: "ERROR", message: error.debugDescription, details: nil))
                      }
                  default:
                      result(FlutterMethodNotImplemented)
                  }
              })
      let backgroundTaskChannel = FlutterMethodChannel(
          name: "com.kodjodevf.mangayomi.background_task",
          binaryMessenger: controller.binaryMessenger
      )
      backgroundTaskChannel.setMethodCallHandler({
          [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
          switch call.method {
          case "begin":
              let args = call.arguments as? Dictionary<String, Any>
              let name = args?["name"] as? String ?? "Mangayomi background task"
              let identifier = UUID().uuidString
              var task: UIBackgroundTaskIdentifier = .invalid
              task = UIApplication.shared.beginBackgroundTask(withName: name) {
                  if task != .invalid {
                      UIApplication.shared.endBackgroundTask(task)
                  }
                  self?.activeBackgroundTasks.removeValue(forKey: identifier)
              }
              if task == .invalid {
                  result(nil)
              } else {
                  self?.activeBackgroundTasks[identifier] = task
                  result(identifier)
              }
          case "end":
              let args = call.arguments as? Dictionary<String, Any>
              guard let identifier = args?["identifier"] as? String,
                    let task = self?.activeBackgroundTasks.removeValue(forKey: identifier) else {
                  result(nil)
                  return
              }
              UIApplication.shared.endBackgroundTask(task)
              result(nil)
          default:
              result(FlutterMethodNotImplemented)
          }
      })

    GeneratedPluginRegistrant.register(with: self)

    if let url = AppLinks.shared.getLink(launchOptions: launchOptions) {
      AppLinks.shared.handleLink(url: url)
      return true
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
