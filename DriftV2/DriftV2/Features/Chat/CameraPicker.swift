//
//  CameraPicker.swift
//  DriftV2
//
//  Thin SwiftUI wrapper over `UIImagePickerController`. Defaults to
//  `.camera`; if running somewhere without a camera (Simulator), falls
//  back to `.photoLibrary` so dev builds keep working. Returns the
//  picked image as JPEG `Data` to the caller.
//

#if os(iOS)
import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    let onPicked: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera)
            ? .camera
            : .photoLibrary
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            defer { parent.dismiss() }
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.85)
            else { return }
            parent.onPicked(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif
