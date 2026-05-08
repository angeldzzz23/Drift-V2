//
//  AudioRecorder.swift
//  DriftV2
//
//  Thin AVAudioRecorder wrapper. Captures mono 16 kHz AAC into a temp file
//  (Whisper-friendly). Handles iOS audio session setup; no-ops on macOS.
//

import Foundation
import AVFoundation

@MainActor
final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private(set) var currentURL: URL?

    var isRecording: Bool { recorder?.isRecording ?? false }

    static func requestPermission() async -> Bool {
        #if os(iOS) || os(visionOS)
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        #else
        await AVCaptureDevice.requestAccess(for: .audio)
        #endif
    }

    func start() throws {
        #if os(iOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        #endif

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec_\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.record() else {
            throw NSError(
                domain: "AudioRecorder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start recording."]
            )
        }
        self.recorder = recorder
        self.currentURL = url
    }

    /// Stop recording and return the file URL of the captured clip, or nil
    /// if nothing was recording.
    func stop() -> URL? {
        recorder?.stop()
        let url = currentURL
        recorder = nil
        currentURL = nil
        deactivateSession()
        return url
    }

    /// Stop and delete the file. Used when the user discards a recording.
    func cancel() {
        recorder?.stop()
        if let url = currentURL {
            try? FileManager.default.removeItem(at: url)
        }
        recorder = nil
        currentURL = nil
        deactivateSession()
    }

    private func deactivateSession() {
        #if os(iOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }
}
