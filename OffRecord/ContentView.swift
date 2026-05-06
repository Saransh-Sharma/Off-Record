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
/// Uses TabView on all devices. On iPadOS 18+, the tab bar adapts to a sidebar.
struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: OffRecordTab = .today

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
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .today:
                    NavigationStack { TodayView() }
                case .timeline:
                    NavigationStack { TimelineView() }
                case .insights:
                    NavigationStack { StatsView() }
                case .friday:
                    NavigationStack { FridayView() }
                case .settings:
                    NavigationStack { SettingsView() }
                }
            }
            .safeAreaPadding(.bottom, 86)

            OffRecordFloatingTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
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
        TabView {
            NavigationStack {
                TodayView()
            }
            .tabItem {
                Label("Today", systemImage: "sun.max")
            }

            NavigationStack {
                TimelineView()
            }
            .tabItem {
                Label("Timeline", systemImage: "list.bullet")
            }

            NavigationStack {
                StatsView()
            }
            .tabItem {
                Label("Insights", systemImage: "chart.bar")
            }

            NavigationStack {
                FridayView()
            }
            .tabItem {
                Label("Friday", systemImage: "sparkles")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
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
}

private struct OffRecordFloatingTabBar: View {
    @Binding var selectedTab: OffRecordTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(OffRecordTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selectedTab = tab
                    }
                    HapticManager.shared.selectionChanged()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                        Text(tab.rawValue)
                            .font(OffRecordTypography.labelSmall)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .foregroundStyle(selectedTab == tab ? OffRecordColor.textBrand : OffRecordColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background {
                        if selectedTab == tab {
                            Capsule()
                                .fill(tab.tint.opacity(0.18))
                                .overlay(Capsule().stroke(tab.tint.opacity(0.32), lineWidth: 1))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(8)
        .background(
            Capsule()
                .fill(OffRecordColor.surfacePrimary.opacity(0.96))
                .overlay(Capsule().stroke(OffRecordColor.borderSoft, lineWidth: 1))
                .shadow(color: OffRecordShadow.tabColor, radius: 30, x: 0, y: 8)
        )
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
