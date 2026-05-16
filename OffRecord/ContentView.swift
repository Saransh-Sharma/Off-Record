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
#if os(iOS)
import UIKit
#endif

/// Main content view with tab-based navigation.
/// Uses TabView on all devices. On iPadOS 18+, the tab bar adapts to a sidebar.
struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var navigationRouter = OffRecordNavigationRouter.shared
    @State private var isKeyboardVisible = false

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: false)],
        animation: .default)
    private var entries: FetchedResults<DiaryEntry>

    var body: some View {
        if horizontalSizeClass == .compact {
            compactTabs
        } else {
            adaptiveTabs
        }
    }

    private var compactTabs: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                switch navigationRouter.selectedTab {
                case .today:
                    NavigationStack {
                        TodayView(
                            compactTabSelection: selectedTabBinding,
                            compactBottomSafeAreaInset: proxy.safeAreaInsets.bottom
                        )
                    }
                case .timeline:
                    NavigationStack { TimelineView() }
                        .safeAreaPadding(.bottom, OffRecordCompactTabBarLayout.reservedContentBottomInset)
                case .insights:
                    NavigationStack { StatsView() }
                        .safeAreaPadding(.bottom, OffRecordCompactTabBarLayout.reservedContentBottomInset)
                case .friday:
                    NavigationStack { FridayView() }
                        .safeAreaPadding(.bottom, OffRecordCompactTabBarLayout.reservedContentBottomInset)
                case .settings:
                    NavigationStack { SettingsView() }
                        .safeAreaPadding(.bottom, OffRecordCompactTabBarLayout.reservedContentBottomInset)
                }

                if navigationRouter.selectedTab != .today {
                    OffRecordFloatingTabBar(selectedTab: selectedTabBinding)
                        .padding(.horizontal, OffRecordCompactTabBarLayout.horizontalPadding)
                        .padding(.bottom, OffRecordCompactTabBarLayout.screenEdgeBottomPadding)
                        .offset(y: isKeyboardVisible ? 0 : proxy.safeAreaInsets.bottom)
                }
            }
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        #endif
        .offRecordScreenBackground()
    }

    @ViewBuilder
    private var adaptiveTabs: some View {
        if #available(iOS 26.0, *) {
            tabs
                .tabViewStyle(.sidebarAdaptable)
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: selectedTabBinding) {
            NavigationStack {
                TodayView()
            }
            .tabItem {
                Label("Today", systemImage: "sun.max")
            }
            .tag(OffRecordTab.today)

            NavigationStack {
                TimelineView()
            }
            .tabItem {
                Label("Timeline", systemImage: "list.bullet")
            }
            .tag(OffRecordTab.timeline)

            NavigationStack {
                StatsView()
            }
            .tabItem {
                Label("Insights", systemImage: "chart.bar")
            }
            .tag(OffRecordTab.insights)

            NavigationStack {
                FridayView()
            }
            .tabItem {
                Label("Friday", systemImage: "sparkles")
            }
            .tag(OffRecordTab.friday)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(OffRecordTab.settings)
        }
    }

    private var selectedTabBinding: Binding<OffRecordTab> {
        Binding(
            get: { navigationRouter.selectedTab },
            set: { navigationRouter.selectedTab = $0 }
        )
    }
}

enum OffRecordCompactTabBarLayout {
    static let horizontalPadding: CGFloat = 16
    static let screenEdgeBottomPadding: CGFloat = 8
    static let todayDockRecordingFeedbackClearance: CGFloat = 112
    static let reservedContentBottomInset: CGFloat = 108
    static let todayDockScrollContentBottomPadding: CGFloat = 244
}

enum OffRecordTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case timeline = "Timeline"
    case insights = "Insights"
    case friday = "Friday"
    case settings = "Settings"

    var id: String { rawValue }

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

struct OffRecordFloatingTabBar: View {
    @Binding var selectedTab: OffRecordTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(OffRecordTab.allCases) { tab in
                Button {
                    select(tab)
                } label: {
                    let style = tab.readableStyle
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                        Text(tab.rawValue)
                            .font(OffRecordTypography.labelSmall)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .foregroundStyle(selectedTab == tab ? selectedForeground(for: tab, style: style) : OffRecordColor.textPrimary.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background {
                        if selectedTab == tab {
                            Capsule()
                                .fill(selectedFill(for: tab, style: style))
                                .overlay(Capsule().stroke(selectedBorder(for: tab, style: style), lineWidth: 1))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityIdentifier("tab.\(tab.rawValue.lowercased())")
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(OffRecordColor.surfacePrimary)
                .overlay(Capsule().stroke(OffRecordColor.borderSoft, lineWidth: 1))
                .shadow(color: OffRecordShadow.tabColor, radius: 30, x: 0, y: 8)
        )
    }

    private func select(_ tab: OffRecordTab) {
        dismissKeyboard()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            selectedTab = tab
        }
        HapticManager.shared.selectionChanged()
    }

    private func dismissKeyboard() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    private func selectedForeground(for tab: OffRecordTab, style: OffRecordReadableTintStyle) -> Color {
        tab == .today ? OffRecordColor.textWarm : style.foreground
    }

    private func selectedFill(for tab: OffRecordTab, style: OffRecordReadableTintStyle) -> Color {
        tab == .today ? OffRecordColor.backgroundPeachTint : style.fill
    }

    private func selectedBorder(for tab: OffRecordTab, style: OffRecordReadableTintStyle) -> Color {
        tab == .today ? OffRecordColor.borderSoft : style.border
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
