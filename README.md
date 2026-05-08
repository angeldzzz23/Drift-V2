# Drift V2

> **DriftV2 is a private, on-device AI app for iPhone and Mac that distributes inference load across your nearby devices — chat with a local MLX LLM (Qwen, Llama, Mistral, Gemma…), dictate prompts through Whisper, and route each request to whichever device on your Wi-Fi has the right model in memory, so your phone can chat against the larger MLX model running on your Mac (or vice-versa) without anything ever leaving your home network.**

It's built on two separate libraries:

- **[ModelKit](../ModelKit)** — downloads, loads, unloads on-device models (MLX LLMs/VLMs, WhisperKit). Single observable `ModelStore`, per-kind cap, lifecycle event stream.
- **[Peerly](../Peerly)** — 1-to-N peer discovery + typed request/streaming over MultipeerConnectivity. Each peer advertises capabilities (services + metadata) on connect.

Drift's job is to compose them into the product above: expose its loaded models as Peerly services, advertise what's loaded, and let the user route chat / mic transcription to *any* connected device that has the right model in memory.

## What it does today

| | Local | Local + remote |
|---|---|---|
| **Chat (LLM)** | Loaded LLM streams replies in-place | Pick a peer's loaded LLM in the connection sheet → prompts go over the wire, chunks stream back |
| **Voice → text (Whisper)** | Mic → local Whisper → drops into draft | Mic on phone, Whisper on Mac, generation on phone — every combination |
| **What's where** | Models tab shows everything on disk + status | Connection sheet shows each peer's full inventory + per-model status |
| **Live observability** | os.Logger + ModelStore.events() | "Hosted activity" sheet streams every served request as it generates |

There is **no automatic routing in this first version** — the user picks "Use for chat" / "Use for transcription" per peer per service. A future version layers something smarter on top (gossip-based health, latency-aware routing, queue length, etc.). The point of v1 is to prove the primitives compose and that the wire format actually carries enough information for a routing algorithm to ever exist.

## Architecture at a glance

```
┌─────────────────────── DriftV2 (per device) ───────────────────────┐
│                                                                    │
│  ┌─ ModelKit ──────┐         ┌─ Peerly ──────────────────────────┐ │
│  │ ModelStore      │         │ PeerService                       │ │
│  │  ├ loadedModels │         │  ├ availablePeers / connectedPeers│ │
│  │  ├ defaults     │  reads  │  ├ peerHellos[id] (services)      │ │
│  │  ├ events()     │ <───────│  ├ register(Service)              │ │
│  │  ├ load/unload  │         │  └ client(of:on:).stream(req)     │ │
│  │  └ delete       │         └────────────────────────────────────┘ │
│  └─────────────────┘                    ▲          ▲                │
│         ▲                              hosts     calls              │
│         │  ChatService(store, log)       │          │               │
│         │  TranscribeService(store, log) │          │               │
│         │                                │          │               │
│  ┌──────┴───────── App layer ────────────┴──────────┴──────────┐    │
│  │  BackendSelection.llm | .whisper                            │    │
│  │      .local | .remote(peer)                                 │    │
│  │  HostActivityLog (sessions served by THIS device)           │    │
│  │  ChatViewModel.send(using: ChatBackend)                     │    │
│  │      ├─ .local(LLMModel)                                    │    │
│  │      └─ .remote(ServiceClient<ChatContract>)                │    │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

Both libraries are unaware of each other. The bridge is a single Swift file pattern: a small `Service` conformance per kind that grabs the loaded model from `ModelStore` and runs the same call the local UI runs.

### `ChatService` — drift.chat over Peerly

```swift
@MainActor final class ChatService: Service {
    typealias Contract = ChatContract
    private weak var store: ModelStore?
    private weak var activityLog: HostActivityLog?

    var metadata: [String: String] {
        // type=llm + a JSON-encoded [ServiceModelInfo] of every downloaded LLM
        // with per-model status (idle/loading/loaded). Re-read by Peerly on
        // every register(...) call → fresh hello broadcast to peers.
    }

    func handle(_ request: ChatRequest, context: ServiceCallContext)
        -> AsyncThrowingStream<ChatChunk, Error>
    {
        // pull loadedModels[.llm] as LLMModel, replay request.turns through
        // ModelKitMLX.LLMModel.stream(turns:), yield each chunk back.
        // log to HostActivityLog so the host's UI shows exactly what was
        // generated.
    }
}
```

`TranscribeService` is the same shape over `WhisperModel.transcribe(audioURL:)`.

### Wire shape (one `models` key, every service)

```jsonc
{
  "type": "llm",
  "models": "[
     {\"id\":\"mlx-community/Qwen2.5-0.5B-Instruct-4bit\",
      \"name\":\"Qwen 2.5 0.5B\",\"sizeGB\":0.4,\"minTier\":\"Phone\",
      \"status\":\"loaded\"},
     ...
  ]"
}
```

Same `ServiceModelInfo` shape for `.chat` and `.transcribe`, so a future routing algorithm parses one schema regardless of the service type.

### Lifecycle that keeps everyone in sync

```
user loads LLM            ModelStore               PeerService                 peers
─────────────             ──────────               ───────────                 ─────
load(entry)        →      .loadStarted             register(chatService) → hello
                          (event)                  ├ refresh advertisedServices
                                                   └ sendHelloToConnectedPeers
                  →       .loaded                  register(chatService)  → hello
unload(entry)     →       .unloaded                register(chatService)  → hello
```

`refreshServicesOnModelEvents` in `DriftV2App` is the loop that connects them — every relevant `ModelStoreEvent` re-registers the same `ChatService`/`TranscribeService` instance, which makes Peerly re-snapshot its `metadata` (now including freshly-computed `loaded` flags) and broadcast a new hello. Peers see the change in their `peerHellos[id]?.services`, the connection sheet redraws, the chat tab's selection check updates.

## Project layout

```
DriftV2/
├── App/
│   ├── DriftV2App.swift        # registers loaders, owns store + peer + selection + activity log
│   ├── ContentView.swift       # TabView (Chat / Models)
│   └── AppLogger.swift         # os.Logger
├── Catalog/
│   └── Catalog.swift           # static list of [ModelEntry] — the menu of models
├── Features/
│   ├── Chat/
│   │   ├── ChatView.swift              # tab UI, computes ChatBackend / TranscribeBackend
│   │   ├── ChatViewModel.swift         # local + remote send, mic state, ChatBackend / TranscribeBackend enums
│   │   ├── ChatService.swift           # drift.chat host over Peerly
│   │   ├── TranscribeService.swift     # drift.transcribe host over Peerly
│   │   ├── ServiceModelInfo.swift      # shared wire-shape decoded by every consumer
│   │   ├── HostActivityLog.swift       # incoming requests + streamed responses, observable
│   │   ├── HostActivityView.swift      # "what's this device serving right now"
│   │   ├── AudioRecorder.swift         # AVAudioRecorder wrapper, mono 16 kHz AAC
│   │   └── Subviews/{ChatBubble, ChatInputBar}.swift
│   ├── Connection/
│   │   ├── ConnectionSheet.swift       # local + connected + available, with selection controls
│   │   ├── BackendSelection.swift      # var llm: LLMSource, var whisper: WhisperSource
│   │   └── Subviews/{DeviceCard, ServicesView}.swift
│   └── ModelManager/
│       ├── ModelManagerView.swift
│       ├── ModelManagerViewModel.swift # default-model persistence, status formatting
│       └── Subviews/{ModelRow, DeviceSummaryRow, StorageFooterSection}.swift
├── Info.plist                          # NSBonjourServices, NSLocalNetworkUsageDescription, NSMicrophoneUsageDescription
└── DriftV2.entitlements                # network.client + .server, audio-input, user-selected files
```

## Setup

DriftV2 expects both libraries as local SPM siblings:

```
~/some/parent/
├── ModelKit/                 # the model-loading library
├── Peerly/                   # the p2p library
└── Drift V2/DriftV2/         # this app
```

The Xcode project references them at `../../ModelKit/ModelKit` and `../../Gemma4Networking/Peerly` (the latter is just where Peerly currently sits — adjust the package path in `project.pbxproj` if you cloned somewhere else).

Required Info.plist keys (all already wired):

- `NSBonjourServices = ["_gemma4._tcp", "_gemma4._udp"]` — required for iOS to even *show* the local-network prompt.
- `NSLocalNetworkUsageDescription` — text shown in that prompt.
- `NSMicrophoneUsageDescription` — text shown for mic access.

macOS sandbox entitlements:

- `com.apple.security.network.client`
- `com.apple.security.network.server`
- `com.apple.security.device.audio-input`
- `com.apple.security.files.user-selected.read-only`

## Try it

1. Build for iPhone (run on device — local network discovery doesn't work in the iOS Simulator) and Mac.
2. On both, **Models tab** → tap the star on a small LLM (Qwen 0.5B) and a Whisper model (Tiny). Defaults persist; the model loads on first appear.
3. On either, **Chat tab** → tap the antenna icon (top-left) → tap **Connect** next to the other device. Both sides flip to "Connected" with full hardware specs.
4. Pick a routing combo by tapping the small "Use for chat" / "Use for transcription" pills under each peer's services:
   - Both on the iPhone (the default) — runs entirely local on phone.
   - "Use for chat" on Mac, "Use for transcription" on iPhone — mic on phone, generation on Mac.
   - Reverse — record on Mac, generate on phone.
5. Hit the mic, speak, tap stop — text drops into the draft.
6. Tap send — the prompt streams back via whichever device you picked.
7. On the *serving* device, tap the rack icon (top-right of Chat tab) to watch incoming calls stream in real time.

## What's missing (intentionally)

- **No routing algorithm.** Selection is manual today. The metadata we send is intentionally rich (`status`, `sizeGB`, `minTier`, full hardware profile via `HelloPayload.profile`) so a v2 can implement gossip-based health checks, queue-aware routing, latency probes, etc., without a wire-format change.
- **No persistence of the backend selection.** `BackendSelection` resets to local on each launch. UserDefaults already powers the default-models list — adding it for the routing selection is straightforward.
- **No multi-hop.** Peerly is a star topology; if A and C aren't directly connected, A can't reach C through B. The v2 path here is replacing the MultipeerConnectivity transport with `NWBrowser`/`NWListener` + a small relay — Peerly's wire format is already transport-agnostic.
- **One generation per kind.** ModelKit's per-kind cap (one LLM, one VLM, one Whisper resident at a time) is a deliberate constraint, not a bug. Loading "Llama" while "Qwen" is loaded swaps in place.
- **JSON base64 audio frames.** Voice is shipped as base64 inside the JSON envelope (33% inflation). For typical short utterances this is fine; long-form audio would benefit from a length-prefixed binary frame on Peerly's roadmap.

## Status

- iOS 18+, macOS 15+ (project default-targets iOS 26 / macOS 26)
- Swift 6.2, strict concurrency on, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`

## License

TBD.
