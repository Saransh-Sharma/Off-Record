//
//  ContentView.swift
//  OffRecord
//
//  Main tab-based navigation container for the app.
//
//  Created by Karthikeyan NG on 01/12/25.
//

import SwiftUI
import CoreData

/// Main content view with tab-based navigation.
/// Uses the native Liquid Glass tab bar on iPhone and an adaptable sidebar on iPad.
/// Voice capture lives in the tab bar's bottom accessory so it's one tap away on every tab.
struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var navigationRouter = OffRecordNavigationRouter.shared
    @ObservedObject private var capture = CaptureController.shared

    var body: some View {
        tabs
            .tabViewStyle(.sidebarAdaptable)
            .tabBarMinimizeBehavior(.onScrollDown)
            .captureAccessory(isHidden: navigationRouter.hidesCaptureAccessory) {
                navigationRouter.requestTypedNote()
            }
            .sheet(isPresented: $capture.isPanelPresented, onDismiss: capture.panelDidDismiss) {
                CapturePanelView()
                    .presentationDetents(capturePanelDetents)
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(OffRecordRadius.xxl)
            }
            .captureAlerts()
            .onReceive(NotificationCenter.default.publisher(for: .startRecordingFromSiri)) { _ in
                startRecordingFromExternalTrigger()
            }
            .onChange(of: navigationRouter.shouldStartRecording) { _, shouldStart in
                guard shouldStart else { return }
                navigationRouter.shouldStartRecording = false
                startRecordingFromExternalTrigger()
            }
            .onAppear {
                if navigationRouter.shouldStartRecording {
                    navigationRouter.shouldStartRecording = false
                    startRecordingFromExternalTrigger()
                }
            }
            .onChange(of: navigationRouter.selectedTab) { _, _ in
                HapticManager.shared.tabChanged()
            }
    }

    private var capturePanelDetents: Set<PresentationDetent> {
        horizontalSizeClass == .regular ? [.large] : [.medium, .large]
    }

    private func startRecordingFromExternalTrigger() {
        guard !capture.phase.isCapturing else {
            capture.isPanelPresented = true
            return
        }
        // Let the launch or route transition settle before the mic sheet appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            capture.startRecording()
        }
    }

    private var tabs: some View {
        TabView(selection: selectedTabBinding) {
            ForEach(OffRecordTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    NavigationStack {
                        tab.rootView
                    }
                }
            }
        }
        .background(tabKeyboardShortcuts)
    }

    /// ⌘1–⌘5 switch tabs; ⌘R starts or stops a recording.
    private var tabKeyboardShortcuts: some View {
        ZStack {
            ForEach(Array(OffRecordTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { navigationRouter.selectedTab = tab }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Button(String(localized: "Record", comment: "Keyboard shortcut (⌘R) that starts or stops a voice recording")) { capture.toggleRecording() }
                .keyboardShortcut("r", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var selectedTabBinding: Binding<OffRecordTab> {
        Binding(
            get: { navigationRouter.selectedTab },
            set: { navigationRouter.selectedTab = $0 }
        )
    }
}

enum OffRecordTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case timeline = "Timeline"
    case insights = "Insights"
    case friday = "Friday"
    case settings = "Settings"

    var id: String { rawValue }

    /// The tab name people see. Raw values stay fixed because routes and UI tests use them.
    var title: String {
        switch self {
        case .today: return String(localized: "Today", comment: "Tab name")
        case .timeline: return String(localized: "Timeline", comment: "Tab name")
        case .insights: return String(localized: "Insights", comment: "Tab name")
        case .friday: return String(localized: "Friday", comment: "Tab name; Friday is the AI companion, not the weekday")
        case .settings: return String(localized: "Settings", comment: "Tab name")
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.max.fill"
        case .timeline: return "book.pages.fill"
        case .insights: return "chart.xyaxis.line"
        case .friday: return "sparkles"
        case .settings: return "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .today: return OffRecordColor.brandPeach
        case .timeline: return OffRecordColor.brandSageDark
        case .insights: return OffRecordColor.brandAqua
        case .friday: return OffRecordColor.brandLavenderDark
        case .settings: return OffRecordColor.brandPlum
        }
    }

    @ViewBuilder
    var rootView: some View {
        switch self {
        case .today: TodayView()
        case .timeline: TimelineView()
        case .insights: StatsView()
        case .friday: FridayView()
        case .settings: SettingsView()
        }
    }

    var readableStyle: OffRecordReadableTintStyle {
        switch self {
        case .today: return .journal
        case .timeline: return .privacy
        case .insights: return .growth
        case .friday: return .friday
        case .settings: return .brand
        }
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

private extension View {
    /// The Record bar as the tab bar's bottom accessory. iOS 26.1 can hide it for screens
    /// with their own composer; on 26.0 it simply stays.
    @ViewBuilder
    func captureAccessory(isHidden: Bool, onWrite: @escaping () -> Void) -> some View {
        if #available(iOS 26.1, *) {
            tabViewBottomAccessory(isEnabled: !isHidden) {
                CaptureAccessoryBar(onWrite: onWrite)
            }
        } else {
            tabViewBottomAccessory {
                CaptureAccessoryBar(onWrite: onWrite)
            }
        }
    }
}
