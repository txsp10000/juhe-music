import Foundation
import UIKit

@objc final class CarPlayDiagnosticLog: NSObject {
  private static let queue = DispatchQueue(label: "com.music.carplay-diagnostics")
  private static let maximumBytes: UInt64 = 256 * 1024

  private static let formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
  }()

  private static var logURL: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("CarPlay-Diagnostics.txt")
  }

  private static var legacyLogURL: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("carplay-diagnostics.log")
  }

  private static func prepareLogFile() {
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: logURL.path),
       fileManager.fileExists(atPath: legacyLogURL.path) {
      try? fileManager.moveItem(at: legacyLogURL, to: logURL)
    }
    if !fileManager.fileExists(atPath: logURL.path) {
      fileManager.createFile(
        atPath: logURL.path,
        contents: nil,
        attributes: [.protectionKey: FileProtectionType.none]
      )
    } else {
      try? fileManager.setAttributes(
        [.protectionKey: FileProtectionType.none],
        ofItemAtPath: logURL.path
      )
    }
  }

  @objc static func write(_ message: String) {
    NSLog("CarPlay diagnostic: %@", message)
    let line = "\(formatter.string(from: Date())) \(message)\n"
    queue.async {
      prepareLogFile()
      guard let handle = FileHandle(forWritingAtPath: logURL.path) else { return }
      defer { try? handle.close() }
      handle.seekToEndOfFile()
      if handle.offsetInFile > maximumBytes {
        handle.truncateFile(atOffset: 0)
      }
      handle.write(line.data(using: .utf8) ?? Data())
      try? handle.synchronize()
    }
  }

  @objc static func read() -> String {
    queue.sync {
      prepareLogFile()
      guard let data = FileManager.default.contents(atPath: logURL.path),
            let contents = String(data: data, encoding: .utf8),
            !contents.isEmpty else {
        return "暂无 CarPlay 诊断记录。连接车机并打开应用后再刷新。"
      }
      return contents
    }
  }

  @objc static func clear() {
    queue.sync {
      try? FileManager.default.removeItem(at: logURL)
      prepareLogFile()
    }
  }

  @objc static func writeLaunchSummary() {
    let info = Bundle.main.infoDictionary ?? [:]
    let version = info["CFBundleShortVersionString"] as? String ?? "?"
    let build = info["CFBundleVersion"] as? String ?? "?"
    let revision = info["CarPlayDiagnosticRevision"] as? String ?? "local"
    let manifest = info["UIApplicationSceneManifest"] as? [String: Any]
    let configurations = manifest?["UISceneConfigurations"] as? [String: Any]
    let roles = configurations?.keys.sorted().joined(separator: ", ") ?? "none"
    write("APP_LAUNCH version=\(version)(\(build)) revision=\(revision) logic=templateDidAppear-v1 iOS=\(UIDevice.current.systemVersion) roles=\(roles)")
  }
}
