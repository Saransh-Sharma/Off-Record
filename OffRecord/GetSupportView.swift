//
//  GetSupportView.swift
//  OffRecord
//
//  Crisis resources shown when an AI surface replies with support copy
//  instead of analysis (`SensitiveResponseMode.supportOnly`). The list is
//  bundled, so it works offline, and keyed by the device region.
//
//  This sheet is the one place the Voice standard allows advice; see
//  "Safety" in OffRecord Design.md.
//

import SwiftUI

struct CrisisHelpline: Identifiable, Equatable {
    let id: String
    /// The service's own name; not translated.
    let name: String
    let callNumber: String?
    let textNumber: String?
}

struct CrisisRegionResources: Equatable {
    let helplines: [CrisisHelpline]
    let emergencyNumber: String
}

enum CrisisResources {
    /// International directory for regions without a bundled helpline.
    static let findAHelpline = URL(string: "https://findahelpline.com")!

    // Each number was checked on the service's own site on 2026-10-01:
    // 988lifeline.org, 988.ca, samaritans.org, lifeline.org.au, 1737.org.nz.
    // Tele-MANAS was checked on findahelpline.com because its site failed TLS.
    static let byRegion: [String: CrisisRegionResources] = [
        "US": .init(helplines: [.init(id: "us-988", name: "988 Suicide & Crisis Lifeline", callNumber: "988", textNumber: "988")], emergencyNumber: "911"),
        "CA": .init(helplines: [.init(id: "ca-988", name: "9-8-8 Suicide Crisis Helpline", callNumber: "988", textNumber: "988")], emergencyNumber: "911"),
        "GB": .init(helplines: [.init(id: "gb-samaritans", name: "Samaritans", callNumber: "116123", textNumber: nil)], emergencyNumber: "999"),
        "IE": .init(helplines: [.init(id: "ie-samaritans", name: "Samaritans", callNumber: "116123", textNumber: nil)], emergencyNumber: "112"),
        "AU": .init(helplines: [.init(id: "au-lifeline", name: "Lifeline", callNumber: "131114", textNumber: "0477131114")], emergencyNumber: "000"),
        "NZ": .init(helplines: [.init(id: "nz-1737", name: "1737 Need to Talk?", callNumber: "1737", textNumber: "1737")], emergencyNumber: "111"),
        "IN": .init(helplines: [.init(id: "in-telemanas", name: "Tele-MANAS", callNumber: "14416", textNumber: nil)], emergencyNumber: "112"),
    ]

    static let fallback = CrisisRegionResources(helplines: [], emergencyNumber: "112")

    static func resources(for regionCode: String?) -> CrisisRegionResources {
        guard let regionCode else { return fallback }
        return byRegion[regionCode.uppercased()] ?? fallback
    }

    static var current: CrisisRegionResources {
        resources(for: Locale.current.region?.identifier)
    }
}

struct GetSupportView: View {
    var resources: CrisisRegionResources = CrisisResources.current
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
                    Text("If you’re thinking about hurting yourself, talk to someone now.")
                        .font(OffRecordTypography.bodyLarge)
                        .foregroundStyle(OffRecordColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(resources.helplines) { helpline in
                        helplineCard(helpline)
                    }

                    actionCard(
                        title: String(localized: "Emergency Services", comment: "Get Support row for calling the local emergency number"),
                        detail: String(localized: "If you’re in danger now"),
                        systemImage: "phone.badge.waveform",
                        actions: [(String(localized: "Call \(resources.emergencyNumber)", comment: "Calls the local emergency number, e.g. Call 911"), telURL(resources.emergencyNumber))],
                        identifier: "getSupport.emergency"
                    )

                    actionCard(
                        title: String(localized: "Someone You Trust", comment: "Get Support row for messaging a friend or family member"),
                        detail: String(localized: "A friend, family member, or doctor"),
                        systemImage: "person.2",
                        actions: [(String(localized: "Message"), URL(string: "sms:"))],
                        identifier: "getSupport.trustedPerson"
                    )

                    actionCard(
                        title: String(localized: "Other Helplines", comment: "Get Support row linking to an international helpline directory"),
                        detail: String(localized: "Free helplines in other countries"),
                        systemImage: "globe",
                        actions: [(String(localized: "Find a Helpline"), CrisisResources.findAHelpline)],
                        identifier: "getSupport.directory"
                    )

                    Text("OffRecord isn’t an emergency service.")
                        .font(OffRecordTypography.metadata)
                        .foregroundStyle(OffRecordColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(OffRecordSpacing.screenX)
                .frame(maxWidth: OffRecordLayout.readableContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(OffRecordAppBackground().ignoresSafeArea())
            .navigationTitle("Get Support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("getSupport.sheet")
    }

    private func helplineCard(_ helpline: CrisisHelpline) -> some View {
        var actions: [(String, URL?)] = []
        if let call = helpline.callNumber {
            actions.append((String(localized: "Call", comment: "Calls a crisis helpline"), telURL(call)))
        }
        if let text = helpline.textNumber {
            actions.append((String(localized: "Text", comment: "Texts a crisis helpline"), URL(string: "sms:\(text)")))
        }
        return actionCard(
            title: helpline.name,
            detail: String(localized: "Free · 24/7", comment: "Crisis helpline availability"),
            systemImage: "phone",
            actions: actions,
            identifier: "getSupport.helpline.\(helpline.id)"
        )
    }

    private func actionCard(
        title: String,
        detail: String,
        systemImage: String,
        actions: [(String, URL?)],
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            HStack(alignment: .top, spacing: OffRecordSpacing.md) {
                OffRecordIconBubble(systemImage: systemImage, tint: OffRecordColor.textBlush, size: 34, iconSize: 15)
                VStack(alignment: .leading, spacing: OffRecordSpacing.xxs) {
                    Text(verbatim: title)
                        .font(OffRecordTypography.cardTitle)
                        .foregroundStyle(OffRecordColor.textHeading)
                    Text(detail)
                        .font(OffRecordTypography.bodySmall)
                        .foregroundStyle(OffRecordColor.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: OffRecordSpacing.sm) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    if let url = action.1 {
                        Link(destination: url) {
                            Text(action.0)
                                .offRecordPillButton()
                        }
                    }
                }
            }
        }
        .padding(OffRecordSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRecordCard(cornerRadius: OffRecordRadius.lg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func telURL(_ number: String) -> URL? {
        URL(string: "tel:\(number)")
    }
}

/// Opens `GetSupportView`. Used wherever a surface shows support copy.
struct GetSupportButton: View {
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label(String(localized: "Get Support"), systemImage: "heart.text.square")
                .offRecordPillButton()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("getSupport.button")
        .sheet(isPresented: $isPresented) {
            GetSupportView()
        }
    }
}
