import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeAppDataFromBackup()
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// appDataRoot（Application Support/Notepad）只存索引、快照、日志与 staging，
  /// 属于本机派生 / 运维数据，不进入 iCloud 设备备份（见 docs/architecture.md 第 12 节）。
  /// 排除标记设在目录上，对其下全部内容生效。
  private func excludeAppDataFromBackup() {
    let fileManager = FileManager.default
    guard
      var directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("Notepad", isDirectory: true)
    else { return }
    do {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try directory.setResourceValues(values)
    } catch {
      NSLog("[Backup] 设置 appDataRoot 备份排除失败: \(error)")
    }
  }
}
