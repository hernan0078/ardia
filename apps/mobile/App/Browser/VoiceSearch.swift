import AVFoundation
import Speech
import SwiftUI

@MainActor
final class VoiceSearch: ObservableObject {
  enum State: Equatable { case idle, listening, denied(String) }

  @Published private(set) var state: State = .idle
  @Published private(set) var transcript = ""
  @Published private(set) var level: CGFloat = 0
  private let engine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var silence: Task<Void, Never>?
  private var finished: ((String) -> Void)?

  func start(_ done: @escaping (String) -> Void) async {
    guard state != .listening else { return }
    finished = done
    transcript = ""
    let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
    guard speech == .authorized else {
      state = .denied("Allow Speech Recognition for Ardia in Settings to search by voice.")
      return
    }
    guard await AVAudioApplication.requestRecordPermission() else {
      state = .denied("Allow the microphone for Ardia in Settings to search by voice.")
      return
    }
    guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
      state = .denied("Voice search isn’t available right now.")
      return
    }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement, options: .duckOthers)
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      let request = SFSpeechAudioBufferRecognitionRequest()
      request.shouldReportPartialResults = true
      if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
      self.request = request
      let input = engine.inputNode
      input.removeTap(onBus: 0)
      input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
        request.append(buffer)
        let level = Self.level(of: buffer)
        Task { @MainActor in self?.level = level }
      }
      engine.prepare()
      try engine.start()
      state = .listening
      waitForSilence(seconds: 4)
      task = recognizer.recognitionTask(with: request) { [weak self] result, error in
        Task { @MainActor in
          guard let self else { return }
          if let result {
            self.transcript = result.bestTranscription.formattedString
            self.waitForSilence(seconds: 1.4)
            if result.isFinal { self.stop(submit: true) }
          } else if error != nil {
            self.stop(submit: true)
          }
        }
      }
    } catch {
      state = .denied("Couldn’t start the microphone.")
      stop(submit: false)
    }
  }

  func stop(submit: Bool) {
    silence?.cancel()
    if engine.isRunning {
      engine.stop()
      engine.inputNode.removeTap(onBus: 0)
    }
    request?.endAudio()
    task?.cancel()
    request = nil
    task = nil
    level = 0
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    let wasListening = state == .listening
    if wasListening { state = .idle }
    let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    if submit, wasListening, !text.isEmpty { finished?(text) }
    finished = nil
  }

  func reset() {
    if case .denied = state { state = .idle }
  }

  private func waitForSilence(seconds: Double) {
    silence?.cancel()
    silence = Task { [weak self] in
      try? await Task.sleep(for: .seconds(seconds))
      guard !Task.isCancelled else { return }
      self?.stop(submit: true)
    }
  }

  nonisolated static func level(of buffer: AVAudioPCMBuffer) -> CGFloat {
    guard let data = buffer.floatChannelData?[0] else { return 0 }
    let n = Int(buffer.frameLength)
    guard n > 0 else { return 0 }
    var sum: Float = 0
    for i in stride(from: 0, to: n, by: 4) { sum += data[i] * data[i] }
    let rms = sqrt(sum / Float(max(1, n / 4)))
    return CGFloat(min(1, max(0, (20 * log10(max(rms, 0.000_01)) + 50) / 45)))
  }
}

struct ListeningView: View {
  @ObservedObject var voice: VoiceSearch

  var body: some View {
    VStack(spacing: 18) {
      ZStack {
        Circle().fill(Color.white.opacity(0.08)).frame(width: 120 + voice.level * 70, height: 120 + voice.level * 70)
        Circle().fill(Color.white.opacity(0.14)).frame(width: 96 + voice.level * 40, height: 96 + voice.level * 40)
        Image(systemName: "mic.fill").font(.system(size: 34, weight: .semibold))
      }
      .frame(height: 200)
      .animation(.easeOut(duration: 0.12), value: voice.level)
      Text(voice.transcript.isEmpty ? "Listening…" : voice.transcript)
        .font(.system(size: 22, weight: .medium))
        .multilineTextAlignment(.center)
        .lineLimit(4)
        .padding(.horizontal, 24)
      Button("Done") { voice.stop(submit: true) }
        .font(.headline)
        .padding(.horizontal, 26)
        .frame(height: 44)
        .background(Color.white.opacity(0.14), in: Capsule())
    }
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 20)
  }
}
