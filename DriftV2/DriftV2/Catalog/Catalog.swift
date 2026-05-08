//
//  Catalog.swift
//  DriftV2
//

import Foundation
import ModelKit

enum Catalog {
    
    static let all: [ModelEntry] = [
        // LLMs (text-only)
        .init(
            "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
            "Qwen 2.5 0.5B",
            .llm,
            0.4,
            .phone,
            note: "Tiny — runs comfortably on iPhone."
        ),
        .init(
            "mlx-community/Llama-3.2-1B-Instruct-4bit",
            "Llama 3.2 1B",
            .llm,
            0.7,
            .phone
        ),
        .init(
            "mlx-community/Llama-3.2-3B-Instruct-4bit",
            "Llama 3.2 3B",
            .llm,
            1.8,
            .phone
        ),
        .init(
            "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
            "Mistral 7B Instruct",
            .llm,
            4.1,
            .tabletOrMac
        ),

        // VLMs (vision + language)
        .init(
            "mlx-community/Qwen2-VL-2B-Instruct-4bit",
            "Qwen2-VL 2B",
            .vlm,
            1.4,
            .phone,
            note: "Vision-capable — accepts images."
        ),
        .init(
            "mlx-community/gemma-4-e2b-it-4bit",
            "Gemma 4 e2b IT (Vision)",
            .vlm,
            1.5,
            .phone
        ),
        .init(
            "mlx-community/gemma-3-4b-it-qat-4bit",
            "Gemma 3 4B Vision",
            .vlm,
            2.8,
            .tabletOrMac
        ),

        // Whisper (speech-to-text)
        .init(
            "openai_whisper-tiny.en",
            "Whisper Tiny (En)",
            .whisper,
            0.04,
            .phone
        ),
        .init(
            "openai_whisper-base.en",
            "Whisper Base (En)",
            .whisper,
            0.14,
            .phone
        ),
        .init(
            "openai_whisper-small.en",
            "Whisper Small (En)",
            .whisper,
            0.46,
            .phone
        ),
        .init(
            "openai_whisper-large-v3-turbo",
            "Whisper Large v3 Turbo",
            .whisper,
            1.6,
            .tabletOrMac,
            note: "Multilingual."
        ),
    ]

    static func grouped() -> [(ModelKind, [ModelEntry])] {
        let order: [ModelKind] = [.llm, .vlm, .whisper]
        return order.compactMap { kind in
            let items = all.filter { $0.kind == kind }
            return items.isEmpty ? nil : (kind, items)
        }
    }
}
