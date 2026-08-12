import Flutter
import UIKit
import AVFAudio
import MediaPlayer
import CommonCrypto
import Darwin

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var lastArtUri: String = ""
  private var cachedArtwork: MPMediaItemArtwork?
  private var nowPlayingChannel: FlutterMethodChannel?
  private var diagnosticsChannel: FlutterMethodChannel?
  private var isPlaybackActive: Bool = false
  private var wasPlayingBeforeInterruption: Bool = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
      try session.setActive(true)
    } catch {}

    UIApplication.shared.beginReceivingRemoteControlEvents()
    setupAudioObservers()

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    DispatchQueue.main.async {
      if let controller = self.window?.rootViewController as? FlutterViewController {
        self.setupNowPlayingChannel(messenger: controller.binaryMessenger)
        self.setupDiagnosticsChannel(messenger: controller.binaryMessenger)
      }
    }

    return result
  }

  // MARK: - Audio Session Observers

  private func setupAudioObservers() {
    let nc = NotificationCenter.default
    nc.addObserver(self, selector: #selector(handleInterruption(_:)),
                   name: AVAudioSession.interruptionNotification, object: nil)
    nc.addObserver(self, selector: #selector(handleRouteChange(_:)),
                   name: AVAudioSession.routeChangeNotification, object: nil)
    nc.addObserver(self, selector: #selector(handleMediaServicesReset(_:)),
                   name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    nc.addObserver(self, selector: #selector(handleSilenceSecondaryAudio(_:)),
                   name: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil)
  }

  private func sendEvent(_ event: String, reason: String, extra: [String: Any] = [:]) {
    DispatchQueue.main.async {
      var arguments = extra
      arguments["event"] = event
      arguments["reason"] = reason
      self.nowPlayingChannel?.invokeMethod("audioEvent", arguments: arguments)
    }
  }

  @objc private func handleInterruption(_ notification: Notification) {
    guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

    switch type {
    case .began:
      wasPlayingBeforeInterruption = isPlaybackActive
      sendEvent("pause", reason: "interruption", extra: [
        "wasPlaying": wasPlayingBeforeInterruption
      ])

    case .ended:
      try? AVAudioSession.sharedInstance().setActive(true)
      let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      let shouldResume = options.contains(.shouldResume) && wasPlayingBeforeInterruption
      wasPlayingBeforeInterruption = false
      if shouldResume {
        sendEvent("resume", reason: "interruption")
      }

    @unknown default: break
    }
  }

  @objc private func handleRouteChange(_ notification: Notification) {
    guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

    let session = AVAudioSession.sharedInstance()

    switch reason {
    case .oldDeviceUnavailable:
      if let previousRoute = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
        let hadExternalOutput = previousRoute.outputs.contains { output in
          [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .carAudio].contains(output.portType)
        }
        let nowSpeaker = session.currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
        if hadExternalOutput && nowSpeaker {
          sendEvent("pause", reason: "routeDisconnected")
        }
      }

    case .newDeviceAvailable:
      break

    case .override:
      sendEvent("pause", reason: "siriOverride")

    case .categoryChange:
      break

    default: break
    }
  }

  @objc private func handleMediaServicesReset(_ notification: Notification) {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
      try session.setActive(true)
    } catch {}
  }

  @objc private func handleSilenceSecondaryAudio(_ notification: Notification) {
    guard let typeValue = notification.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt,
          let type = AVAudioSession.SilenceSecondaryAudioHintType(rawValue: typeValue) else { return }

    switch type {
    case .begin:
      sendEvent("pause", reason: "secondaryAudio")
    case .end:
      break
    @unknown default: break
    }
  }

  private func setupNowPlayingChannel(messenger: FlutterBinaryMessenger) {
    guard nowPlayingChannel == nil else { return }
    let channel = FlutterMethodChannel(
      name: "com.music/nowplaying",
      binaryMessenger: messenger
    )
    nowPlayingChannel = channel
    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { result(nil); return }
      if call.method == "update", let args = call.arguments as? [String: Any] {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        var artworkToLoad: String?
        if let title = args["title"] as? String, !title.isEmpty {
          info[MPMediaItemPropertyTitle] = title
        }
        if let artist = args["artist"] as? String, !artist.isEmpty {
          info[MPMediaItemPropertyArtist] = artist
        }
        if let album = args["album"] as? String, !album.isEmpty {
          info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let duration = args["duration"] as? Double, duration > 0 {
          info[MPMediaItemPropertyPlaybackDuration] = NSNumber(value: duration)
        }
        if let elapsed = args["elapsedTime"] as? Double {
          info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: elapsed)
        }
        let playbackRate = (args["playbackRate"] as? Double) ?? 1.0
        self.isPlaybackActive = playbackRate > 0
        info[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate

        let artUri = (args["artUri"] as? String) ?? ""
        if artUri != self.lastArtUri {
          self.lastArtUri = artUri
          self.cachedArtwork = nil
          info.removeValue(forKey: MPMediaItemPropertyArtwork)
          if !artUri.isEmpty {
            artworkToLoad = artUri
          }
        } else if let artwork = self.cachedArtwork {
          info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if let artworkToLoad = artworkToLoad {
          self.loadArtwork(from: artworkToLoad)
        }
        result(nil)
      }
    }
  }

  private func setupDiagnosticsChannel(messenger: FlutterBinaryMessenger) {
    guard diagnosticsChannel == nil else { return }
    let channel = FlutterMethodChannel(
      name: "com.music/diagnostics",
      binaryMessenger: messenger
    )
    diagnosticsChannel = channel
    channel.setMethodCallHandler { (call, result) in
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_arguments", message: "Missing arguments", details: nil))
        return
      }
      switch call.method {
      case "log":
        NSLog("AudioCacheService: %@", args["message"] as? String ?? "")
        result(nil)
      case "decryptAudioFile":
        guard let path = args["path"] as? String,
              let keyHex = args["keyHex"] as? String,
              let table = args["sampleTable"] as? FlutterStandardTypedData else {
          result(FlutterError(
            code: "invalid_arguments",
            message: "Missing native decrypt arguments",
            details: nil
          ))
          return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          let startedAt = DispatchTime.now().uptimeNanoseconds
          do {
            try self.decryptAudioFile(path: path, keyHex: keyHex, sampleTable: table.data)
            let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000)
            DispatchQueue.main.async { result(elapsedMs) }
          } catch {
            NSLog("AudioCacheService: native audio decrypt failed: %@", error.localizedDescription)
            DispatchQueue.main.async {
              result(FlutterError(
                code: "native_decrypt_failed",
                message: error.localizedDescription,
                details: nil
              ))
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func decryptAudioFile(path: String, keyHex: String, sampleTable: Data) throws {
    let key = try decodeHex(keyHex)
    guard key.count == kCCKeySizeAES128 else {
      throw nativeDecryptError("AES-128 key must contain 32 hex characters")
    }
    guard sampleTable.count % 24 == 0 else {
      throw nativeDecryptError("Invalid CENC sample table")
    }

    let fd = open(path, O_RDWR)
    guard fd >= 0 else {
      throw nativeDecryptError("Unable to open decrypted audio output")
    }
    defer { close(fd) }

    var fileInfo = stat()
    guard fstat(fd, &fileInfo) == 0, fileInfo.st_size > 0 else {
      throw nativeDecryptError("Unable to read decrypted audio output size")
    }
    let fileSize = Int(fileInfo.st_size)
    guard let mapping = mmap(
      nil,
      fileSize,
      PROT_READ | PROT_WRITE,
      MAP_SHARED,
      fd,
      0
    ), mapping != MAP_FAILED else {
      throw nativeDecryptError("Unable to map decrypted audio output")
    }
    defer { munmap(mapping, fileSize) }

    let table = [UInt8](sampleTable)
    var maximumSampleLength = 0
    for recordOffset in stride(from: 0, to: table.count, by: 24) {
      maximumSampleLength = max(maximumSampleLength, readUInt32(table, recordOffset + 4))
    }
    var output = [UInt8](repeating: 0, count: maximumSampleLength)

    for recordOffset in stride(from: 0, to: table.count, by: 24) {
      let offset = readUInt32(table, recordOffset)
      let length = readUInt32(table, recordOffset + 4)
      guard offset <= fileSize - length else {
        throw nativeDecryptError("Invalid CENC sample offset")
      }
      let iv = Array(table[(recordOffset + 8)..<(recordOffset + 24)])
      var cryptor: CCCryptorRef?
      let createStatus = key.withUnsafeBytes { keyBuffer in
        iv.withUnsafeBytes { ivBuffer in
          CCCryptorCreateWithMode(
            CCOperation(kCCDecrypt),
            CCMode(kCCModeCTR),
            CCAlgorithm(kCCAlgorithmAES),
            CCPadding(ccNoPadding),
            ivBuffer.baseAddress,
            keyBuffer.baseAddress,
            key.count,
            nil,
            0,
            0,
            CCModeOptions(kCCModeOptionCTR_BE),
            &cryptor
          )
        }
      }
      guard createStatus == kCCSuccess, let activeCryptor = cryptor else {
        throw nativeDecryptError("Unable to initialize AES-CTR: \(createStatus)")
      }

      var moved = 0
      let updateStatus = output.withUnsafeMutableBytes { outputBuffer in
        CCCryptorUpdate(
          activeCryptor,
          mapping.advanced(by: offset),
          length,
          outputBuffer.baseAddress,
          length,
          &moved
        )
      }
      CCCryptorRelease(activeCryptor)
      guard updateStatus == kCCSuccess, moved == length else {
        throw nativeDecryptError("AES-CTR update failed: \(updateStatus)")
      }
      output.withUnsafeBytes { outputBuffer in
        memcpy(mapping.advanced(by: offset), outputBuffer.baseAddress!, moved)
      }
    }
  }

  private func decodeHex(_ value: String) throws -> [UInt8] {
    guard value.count % 2 == 0 else {
      throw nativeDecryptError("Invalid AES key hex")
    }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(value.count / 2)
    var index = value.startIndex
    while index < value.endIndex {
      let next = value.index(index, offsetBy: 2)
      guard let byte = UInt8(value[index..<next], radix: 16) else {
        throw nativeDecryptError("Invalid AES key hex")
      }
      bytes.append(byte)
      index = next
    }
    return bytes
  }

  private func readUInt32(_ bytes: [UInt8], _ offset: Int) -> Int {
    return Int(bytes[offset]) << 24
      | Int(bytes[offset + 1]) << 16
      | Int(bytes[offset + 2]) << 8
      | Int(bytes[offset + 3])
  }

  private func nativeDecryptError(_ message: String) -> NSError {
    return NSError(
      domain: "com.music.audio-decrypt",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }

  private func loadArtwork(from urlString: String) {
    if urlString.hasPrefix("file://") || urlString.hasPrefix("/") {
      let path = urlString.hasPrefix("file://")
        ? (URL(string: urlString)?.path ?? String(urlString.dropFirst(7)))
        : urlString
      guard let data = FileManager.default.contents(atPath: path),
            let image = UIImage(data: data) else { return }
      let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
      DispatchQueue.main.async {
        guard self.lastArtUri == urlString else { return }
        self.cachedArtwork = artwork
        if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
          info[MPMediaItemPropertyArtwork] = artwork
          MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
      }
      return
    }
    guard let url = URL(string: urlString) else { return }
    var request = URLRequest(url: url)
    request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      guard let self = self, let data = data, !data.isEmpty,
            let image = UIImage(data: data) else { return }
      let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
      DispatchQueue.main.async {
        guard self.lastArtUri == urlString else { return }
        self.cachedArtwork = artwork
        if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
          info[MPMediaItemPropertyArtwork] = artwork
          MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
      }
    }.resume()
  }
}
