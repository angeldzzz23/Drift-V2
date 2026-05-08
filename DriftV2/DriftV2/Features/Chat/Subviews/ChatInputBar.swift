//
//  ChatInputBar.swift
//  DriftV2
//

import SwiftUI
import UniformTypeIdentifiers
import ModelKitMLX
import ModelKitWhisper

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ChatInputBar: View {
    @Bindable var vm: ChatViewModel
    let backend: ChatBackend?
    let transcribeBackend: TranscribeBackend?

    @State private var showImagePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let attachment = vm.imageAttachment {
                attachmentPreview(attachment)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $vm.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .disabled(textFieldDisabled)
                    .onSubmit(send)
                    .submitLabel(.send)

                cameraButton
                micButton
                actionButton
            }
        }
        .padding()
        .background(.bar)
        #if os(iOS)
        .fullScreenCover(isPresented: $showImagePicker) {
            CameraPicker { data in
                vm.attach(imageData: data)
            }
            .ignoresSafeArea()
        }
        #elseif os(macOS)
        .fileImporter(
            isPresented: $showImagePicker,
            allowedContentTypes: [.image]
        ) { result in
            if case .success(let url) = result {
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    vm.attach(imageData: data)
                }
            }
        }
        #endif
    }

    private var textFieldDisabled: Bool {
        backend == nil || vm.isGenerating || vm.isRecording || vm.isTranscribing
    }

    @ViewBuilder
    private var cameraButton: some View {
        Button {
            showImagePicker = true
        } label: {
            Image(systemName: "camera.fill")
                .font(.title2)
        }
        .buttonStyle(.plain)
        .disabled(vm.imageAttachment != nil
                  || vm.isGenerating
                  || vm.isRecording
                  || vm.isTranscribing)
    }

    @ViewBuilder
    private func attachmentPreview(_ attachment: ChatImageAttachment) -> some View {
        HStack {
            ZStack(alignment: .topTrailing) {
                thumbnail(for: attachment)
                Button(action: vm.removeImageAttachment) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.65))
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel("Remove image")
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func thumbnail(for attachment: ChatImageAttachment) -> some View {
        let frame = CGSize(width: 64, height: 64)
        if let image = Image(attachmentData: attachment.data) {
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: frame.width, height: frame.height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
                )
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.gray.opacity(0.2))
                .frame(width: frame.width, height: frame.height)
                .overlay {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
        }
    }

    @ViewBuilder
    private var micButton: some View {
        if vm.isTranscribing {
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 28)
        } else if vm.isRecording {
            Button(role: .destructive, action: stopAndTranscribe) {
                Image(systemName: "stop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)
            }
            .buttonStyle(.plain)
        } else {
            Button(action: startRecording) {
                Image(systemName: "mic.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!vm.canRecord(transcribeBackend: transcribeBackend))
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if vm.isGenerating {
            Button(role: .destructive, action: vm.stop) {
                Image(systemName: "stop.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
        } else {
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!vm.canSend(backend: backend))
        }
    }

    private func send() {
        if let backend { vm.send(using: backend) }
    }

    private func startRecording() {
        Task { await vm.startRecording() }
    }

    private func stopAndTranscribe() {
        guard let backend = transcribeBackend else { return }
        Task { await vm.stopAndTranscribe(using: backend) }
    }
}

// MARK: - Cross-platform Image from Data

private extension Image {
    init?(attachmentData data: Data) {
        #if canImport(UIKit)
        guard let img = UIImage(data: data) else { return nil }
        self.init(uiImage: img)
        #elseif canImport(AppKit)
        guard let img = NSImage(data: data) else { return nil }
        self.init(nsImage: img)
        #else
        return nil
        #endif
    }
}

