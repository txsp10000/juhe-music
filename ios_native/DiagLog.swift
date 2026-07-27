import Foundation
import UIKit

@objc class DiagLog: NSObject {
  private static let queue = DispatchQueue(label: "com.miaomiao.music.diaglog")
  private static let maxBytes: UInt64 = 512 * 1024
  private static var didWriteHeader = false

  private static let formatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MM-dd HH:mm:ss.SSS"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
  }()

  @objc static var logPath: String {
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return dir.appendingPathComponent("diag.log").path
  }

  @objc static func log(_ tag: String, _ message: String) {
    let line = "\(formatter.string(from: Date())) [\(tag)] \(message)\n"
    NSLog("DIAG [\(tag)] \(message)")
    queue.async {
      writeHeaderIfNeeded()
      append(line)
    }
  }

  private static func append(_ text: String) {
    let path = logPath
    let fm = FileManager.default
    if !fm.fileExists(atPath: path) {
      fm.createFile(atPath: path, contents: nil)
    }
    guard let handle = FileHandle(forWritingAtPath: path) else { return }
    defer { try? handle.close() }
    handle.seekToEndOfFile()
    if handle.offsetInFile > maxBytes {
      handle.truncateFile(atOffset: 0)
      let note = "--- 日志超过 512KB 已清空 ---\n"
      handle.write(note.data(using: .utf8) ?? Data())
    }
    handle.write(text.data(using: .utf8) ?? Data())
    try? handle.synchronize()
  }

  private static func writeHeaderIfNeeded() {
    guard !didWriteHeader else { return }
    didWriteHeader = true
    let info = Bundle.main.infoDictionary
    let ver = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    let dev = UIDevice.current
    var header = "\n========== 启动 \(formatter.string(from: Date())) ==========\n"
    header += "设备: \(dev.model)  iOS \(dev.systemVersion)\n"
    header += "版本: \(ver) (\(build))\n"
    let manifest = info?["UIApplicationSceneManifest"] as? [String: Any]
    let multi = manifest?["UIApplicationSupportsMultipleScenes"] as? Bool
    let cfgs = manifest?["UISceneConfigurations"] as? [String: Any]
    header += "多场景: \(multi.map { String($0) } ?? "未设置")\n"
    header += "场景角色: \(cfgs?.keys.sorted().joined(separator: ", ") ?? "无")\n"
    header += "==============================================\n"
    append(header)
  }

  @objc static func readAll() -> String {
    guard let data = FileManager.default.contents(atPath: logPath),
          let text = String(data: data, encoding: .utf8) else {
      return "(日志为空)"
    }
    return text
  }

  @objc static func clear() {
    queue.async {
      try? FileManager.default.removeItem(atPath: logPath)
      didWriteHeader = false
    }
  }
}
