//
//  SavingsViews.swift
//  Dock Finder
//
//  The savings card on the home screen and the dashboard behind it: full
//  docks avoided, hands-free checks, minutes saved and what that's worth
//  at the e-bike rate, plus how often the rider didn't take out their phone.
//

import SwiftUI

/// The home screen card. Before any measured savings, it shows the typical
/// commuter estimate, clearly labeled.
struct SavingsCard: View {
    private let savings = SavingsStore.shared

    var body: some View {
        let month = savings.thisMonth
        HStack(spacing: 14) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Savings")
                    .font(.headline)
                if !savings.hasMeasuredSavings {
                    Text("A typical commuter saves about \(Self.minutes(SavingsModel.typicalMonthlyMinutes)) and \(Self.money(SavingsModel.dollars(forMinutes: SavingsModel.typicalMonthlyMinutes))) a month by skipping full docks and never stopping to check their phone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("This month: \(Self.money(month.dollars)) · \(Self.minutes(month.minutes)) saved")
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

    var body: some View {
        List {
            Section("This Month") {
                summaryRows(savings.thisMonth)
            }
            Section("All Time") {
                summaryRows(savings.allTime)
            }
            Section {
                Label(SavingsCard.phoneFree(savings.allTime.handsFreeChecks), systemImage: "iphone.slash")
                    .font(.headline)
            } header: {
                Text("Safety")
            } footer: {
                Text("Each time Dock Finder told you where to dock by voice (Siri, ride alerts, arriving at a saved place), you didn't have to stop, unlock your phone or look down at a map while riding.")
            }
            if !savings.events.isEmpty {
                Section("Recent") {
                    ForEach(savings.events.suffix(15).reversed()) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Skipped \(event.avoided.spokenName) (\(event.avoided.problem)) for \(Speech.stationName(event.chosenName))")
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(event.date.formatted(date: .abbreviated, time: .shortened)) · about \(SavingsCard.minutes(event.minutes)), \(SavingsCard.money(event.dollars))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("How We Calculate This") {
                Text("Each time Dock Finder steers you away from a full or closed dock, we compare two trips: riding to that dock, finding it full and riding on to one with room, versus riding straight to the one with room. The extra distance on city streets at about 15 km/h, plus 1.5 minutes for finding the dock full and picking another, is the time saved (at most 15 minutes per dock).")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Every dock answer by voice also counts as a hands-free check, worth \(SavingsCard.minutes(SavingsModel.handsFreeMinutes)): the time it takes to pull over, unlock your phone, open the Citi Bike map and find a dock. Voice answers within 5 minutes of each other count once.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Money is that time at Citi Bike's member e-bike rate of \(SavingsCard.money(SavingsModel.ebikeDollarsPerMinute)) a minute. These are estimates; the same redirect shown twice within half an hour counts once.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("Savings")
    }

    @ViewBuilder
    private func summaryRows(_ summary: SavingsSummary) -> some View {
        LabeledContent("Money saved", value: SavingsCard.money(summary.dollars))
        LabeledContent("Time saved", value: SavingsCard.minutes(summary.minutes))
        LabeledContent("Full docks avoided", value: "\(summary.fullDocksAvoided) · \(SavingsCard.minutes(summary.fullDockMinutes))")
        LabeledContent("Hands-free checks", value: "\(summary.handsFreeChecks) · \(SavingsCard.minutes(summary.handsFreeMinutes))")
    }
}
