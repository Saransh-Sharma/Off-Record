// swift-tools-version: 6.0
//
//  JournalKit — shared journal technology for OffRecord and LifeBoard.
//
//  Products are extracted incrementally from the OffRecord app. Both apps
//  reference this package locally; the repos must remain sibling directories
//  under the same parent (…/Projects/OffRecord and …/Projects/Tasker) because
//  LifeBoard references it via relative path.
//
//  Storage stays app-side: engines operate over protocol seams defined in
//  JournalFoundation (JournalSnapshotProviding etc.), never over Core Data.
//

import PackageDescription

let package = Package(
    name: "JournalKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
        .macCatalyst(.v17),
    ],
    products: [
        .library(name: "JournalFoundation", targets: ["JournalFoundation"]),
        .library(name: "TranscriptionKit", targets: ["TranscriptionKit"]),
        .library(name: "MoodDialKit", targets: ["MoodDialKit"]),
        .library(name: "SemanticMemoryKit", targets: ["SemanticMemoryKit"]),
        .library(name: "KnowledgeGraphKit", targets: ["KnowledgeGraphKit"]),
        .library(name: "ReflectionKit", targets: ["ReflectionKit"]),
        .library(name: "AssistantCoreKit", targets: ["AssistantCoreKit"]),
        .library(name: "WatchCaptureKit", targets: ["WatchCaptureKit"]),
        .library(name: "JournalSecurityKit", targets: ["JournalSecurityKit"]),
    ],
    targets: [
        .target(
            name: "JournalFoundation"
        ),
        .target(
            name: "TranscriptionKit",
            resources: [
                .process("Localizable.xcstrings")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .target(
            name: "MoodDialKit",
            dependencies: ["JournalFoundation"],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .target(
            name: "SemanticMemoryKit",
            dependencies: ["JournalFoundation"],
            resources: [
                .process("Localizable.xcstrings")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .target(
            name: "KnowledgeGraphKit",
            dependencies: ["JournalFoundation"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .target(
            name: "ReflectionKit",
            dependencies: ["JournalFoundation", "SemanticMemoryKit"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .target(
            name: "AssistantCoreKit",
            dependencies: ["JournalFoundation", "SemanticMemoryKit", "KnowledgeGraphKit", "ReflectionKit"],
            resources: [
                .process("Localizable.xcstrings")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .target(
            name: "WatchCaptureKit",
            resources: [
                .process("Localizable.xcstrings")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .target(
            name: "JournalSecurityKit",
            dependencies: ["JournalFoundation", "ReflectionKit"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "JournalKitTests",
            dependencies: ["JournalFoundation", "TranscriptionKit", "MoodDialKit", "SemanticMemoryKit", "KnowledgeGraphKit", "ReflectionKit", "AssistantCoreKit", "WatchCaptureKit", "JournalSecurityKit"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
    ]
)
