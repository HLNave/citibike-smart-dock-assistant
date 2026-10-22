//
//  SavingsViews.swift
//  Dock Finder
//
//  The savings card on the home screen and the dashboard behind it: full
//  docks avoided, hands-free checks, minutes saved and what that's worth
//  on the rider's plan (member or not, e-bike or classic, picked here),
//  plus how often the rider didn't take out their phone.
//

import SwiftUI

/// The home screen card. Before any measured savings, it shows the typical
/// commuter estimate, clearly labeled.
struct SavingsCard: View {
    private let savings = SavingsStore.shared
    // Watched so the card updates when the plan changes on the Savings screen.
    @AppStorage(RiderPlan.membershipKey) private var membership = RiderPlan.Membership.member.rawValue
    @AppStorage(RiderPlan.bikeKey) private var bike = RiderPlan.Bike.ebike.rawValue

    var body: some View {
        let month = savings.thisMonth
        let plan = RiderPlan(membershipRawValue: membership, bikeRawValue: bike)
        HStack(spacing: 14) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Savings")
                    .font(.headline)
                if !savings.hasMeasuredSavings {
                    Text(Self.typicalCommuter(plan))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(plan.savesMoney
                         ? "This month: \(Self.money(month.dollars(on: plan))) · \(Self.minutes(month.minutes)) saved"
                         : "This month: \(Self.minutes(month.minutes)) saved")
                        .font(.subheadline.weight(.semibold))
                    Text(Self.fullDocks(month.fullDocksAvoided))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(Self.phoneFree(month.handsFreeChecks), systemImage: "iphone.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .contentShape(.rect)
    }

    static func typicalCommuter(_ plan: RiderPlan) -> String {
        let minutes = SavingsModel.typicalMonthlyMinutes
        let saved = plan.savesMoney
            ? "\(Self.minutes(minutes)) and \(Self.money(SavingsModel.dollars(forMinutes: minutes, plan: plan)))"
            : Self.minutes(minutes)
        return "A typical commuter saves about \(saved) a month by skipping full docks and never stopping to check their phone."
    }

    static func fullDocks(_ count: Int) -> String {
        count == 1 ? "1 full dock avoided" : "\(count) full docks avoided"
    }

    /// The safety stat: "12 times you didn't take out your phone".
    static func phoneFree(_ count: Int) -> String {
        count == 1 ? "1 time you didn't take out your phone" : "\(count) times you didn't take out your phone"
    }

    static func money(_ dollars: Double) -> String {
        dollars.formatted(.currency(code: "USD"))
    }

    static func minutes(_ minutes: Double) -> String {
        let rounded = Int(minutes.rounded())
        if rounded < 60 { return rounded == 1 ? "1 minute" : "\(rounded) minutes" }
        let hours = Double(rounded) / 60
        return "\(hours.formatted(.number.precision(.fractionLength(0...1)))) hours"
    }
}

struct SavingsView: View {
    private let savings = SavingsStore.shared
    @AppStorage(RiderPlan.membershipKey) private var membership = RiderPlan.Membership.member.rawValue
    @AppStorage(RiderPlan.bikeKey) private var bike = RiderPlan.Bike.ebike.rawValue

    private var plan: RiderPlan {
        RiderPlan(membershipRawValue: membership, bikeRawValue: bike)
    }

    static let timeSavedInfo = "Each time Dock Finder steers you away from a full or closed dock, we compare two trips: riding to that dock, finding it full and riding on to one with room, versus riding straight to the one with room. The extra distance on city streets at about 15 km/h, plus 1.5 minutes for finding the dock full and picking another, is the time saved (at most 15 minutes per dock).\n\nEvery dock answer by voice also counts as a hands-free check, worth \(SavingsCard.minutes(SavingsModel.handsFreeMinutes)): the time it takes to pull over, unlock your phone, open the Citi Bike map and find a dock. Voice answers within 5 minutes of each other count once."
    static func moneySavedInfo(_ plan: RiderPlan) -> String {
        switch (plan.membership, plan.bike) {
        case (.member, .ebike):
            "The time saved, at Citi Bike's member e-bike rate of \(SavingsCard.money(SavingsModel.memberEbikeDollarsPerMinute)) a minute."
        case (.nonMember, .ebike):
            "The time saved, at Citi Bike's e-bike rate without a membership, \(SavingsCard.money(SavingsModel.nonMemberEbikeDollarsPerMinute)) a minute."
        case (.member, .classic):
            "Members' classic bike rides include their first 45 minutes, so a detour costs you time, not money. Your savings are the time saved."
        case (.nonMember, .classic):
            "A classic bike ride includes its first 30 minutes, so a detour costs you time, not money. Your savings are the time saved."
        }
    }
    static let safetyInfo = "Each time Dock Finder told you where to dock by voice (Siri, ride alerts, arriving at a saved place), you didn't have to stop, unlock your phone or look down at a map while riding."

    var body: some View {
        List {
            Section {
                Picker("Membership", selection: $membership) {
                    Text("Member").tag(RiderPlan.Membership.member.rawValue)
                    Text("Not a Member").tag(RiderPlan.Membership.nonMember.rawValue)
                }
                Picker("Usually Ride", selection: $bike) {
                    Text("E-bike").tag(RiderPlan.Bike.ebike.rawValue)
                    Text("Classic").tag(RiderPlan.Bike.classic.rawValue)
                }
            } header: {
                Text("Your Citi Bike")
            } footer: {
                Text("Savings are worked out for how you ride.")
            }
            Section("This Month") {
                summaryRows(savings.thisMonth, explained: true)
            }
            Section("All Time") {
                summaryRows(savings.allTime, explained: false)
            }
            Section {
                Label(SavingsCard.phoneFree(savings.allTime.handsFreeChecks), systemImage: "iphone.slash")
                    .font(.headline)
            } header: {
                InfoHeader("Safety", message: Self.safetyInfo)
            }
            if !savings.events.isEmpty {
                Section("Recent") {
                    ForEach(savings.events.suffix(15).reversed()) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Skipped \(event.avoided.spokenName) (\(event.avoided.problem)) for \(Speech.stationName(event.chosenName))")
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(plan.savesMoney
                                 ? "\(event.date.formatted(date: .abbreviated, time: .shortened)) · about \(SavingsCard.minutes(event.minutes)), \(SavingsCard.money(event.dollars(on: plan)))"
                                 : "\(event.date.formatted(date: .abbreviated, time: .shortened)) · about \(SavingsCard.minutes(event.minutes))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Savings")
        .onChange(of: plan) { _, plan in
            Metrics.shared.log("plan_changed", details: ["membership": plan.membership.rawValue, "bike": plan.bike.rawValue])
        }
    }

    /// `explained` adds the ⓘ after money and time saved (in the top section only).
    @ViewBuilder
    private func summaryRows(_ summary: SavingsSummary, explained: Bool) -> some View {
        LabeledContent("Money saved") {
            HStack(spacing: 6) {
                Text(SavingsCard.money(summary.dollars(on: plan)))
                if explained { InfoButton("Money saved", message: Self.moneySavedInfo(plan)) }
            }
        }
        LabeledContent("Time saved") {
            HStack(spacing: 6) {
                Text(SavingsCard.minutes(summary.minutes))
                if explained { InfoButton("Time saved", message: Self.timeSavedInfo) }
            }
        }
        LabeledContent("Full docks avoided", value: "\(summary.fullDocksAvoided) · \(SavingsCard.minutes(summary.fullDockMinutes))")
        LabeledContent("Hands-free checks", value: "\(summary.handsFreeChecks) · \(SavingsCard.minutes(summary.handsFreeMinutes))")
    }
}
