//
//  OnDeviceRecovery.swift
//  Dock Finder
//
//  A second try, with Apple's on-device language model, when the place or
//  station a rider named can't be found: the model rewrites a place
//  description into a search the map understands, or picks which of the
//  closest station names the rider meant. Everything stays on the iPhone.
//  Where Apple Intelligence isn't available, both give up straight away
//  and the rider hears the usual "couldn't find" message.
//

import Foundation
import FoundationModels

// MARK: - Places

nonisolated protocol PlaceQueryRewriting: Sendable {
    /// A search the map is likelier to find ("Russ & Daughters, 179 East
    /// Houston Street" for "that bagel place on Houston"), or `nil` when
    /// there's no better one.
    func rewrite(_ description: String) async -> String?
}

@Generable
nonisolated struct ModelPlaceSearch {
    @Guide(description: "A short Apple Maps search for the place: its official name or its street address. Empty if you don't know the place.")
    var query: String
}

nonisolated struct OnDeviceModelPlaceRewriter: PlaceQueryRewriting {
    private static let instructions = """
        Turn this description of a place in New York City into a short Apple Maps search: \
        an official name or a street address. If you don't know it, return an empty string.
        """

    func rewrite(_ description: String) async -> String? {
        guard OnDeviceModelParser.isAvailable else { return nil }
        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(
                to: description,
                generating: ModelPlaceSearch.self,
                options: GenerationOptions(samplingMode: .greedy)
            )
            let query = response.content.query.trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty ? nil : query
        } catch {
            return nil
        }
    }
}

// MARK: - Stations

/// One station the rider may have meant.
nonisolated struct StationChoice: Sendable, Equatable {
    let id: String
    let name: String
}

nonisolated protocol StationPicking: Sendable {
    /// The ID of the station in `candidates` the rider meant by `spoken`
    /// ("mercy and bleaker"), or `nil` when it's none of them.
    func pick(_ spoken: String, from candidates: [StationChoice]) async -> String?
}

nonisolated struct OnDeviceModelStationPicker: StationPicking {
    static let noneOfThem = "None of these"

    private static let instructions = """
        A Citi Bike rider in New York City said the name of a station, possibly misheard or shortened. \
        Choose the station from the list that they most likely meant. If none of them fits, choose "\(noneOfThem)".
        """

    func pick(_ spoken: String, from candidates: [StationChoice]) async -> String? {
        guard OnDeviceModelParser.isAvailable, !candidates.isEmpty else { return nil }
        // The answer can only be one of these names, so it's always a real station.
        var names: [String] = []
        for candidate in candidates where !names.contains(candidate.name) {
            names.append(candidate.name)
        }
        let list = names.map { "- \($0)" }.joined(separator: "\n")
        do {
            let schema = try GenerationSchema(
                root: DynamicGenerationSchema(
                    name: "StationChoice",
                    description: "The station the rider meant, or \(Self.noneOfThem).",
                    anyOf: names + [Self.noneOfThem]
                ),
                dependencies: []
            )
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(
                to: "The rider said: \"\(spoken)\"\nStations:\n\(list)",
                schema: schema,
                options: GenerationOptions(samplingMode: .greedy)
            )
            let chosen = try response.content.value(String.self)
            return candidates.first { $0.name == chosen }?.id
        } catch {
            return nil
        }
    }
}
