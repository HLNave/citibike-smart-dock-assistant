//
//  InfoButton.swift
//  Dock Finder
//
//  The small blue ⓘ next to a label: tap it for a short explanation in a
//  popover, instead of a paragraph of fine print on the screen.
//

import SwiftUI

struct InfoButton: View {
    let title: LocalizedStringKey
    let message: Text

    @State private var isShowing = false

    init(_ title: LocalizedStringKey, message: Text) {
        self.title = title
        self.message = message
    }

    init(_ title: LocalizedStringKey, message: String) {
        self.init(title, message: Text(message))
    }

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Image(systemName: "info.circle")
                .imageScale(.medium)
                .foregroundStyle(.tint)
        }
        // In a list row, only the icon reacts to taps, not the whole row.
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("About \(Text(title))"))
        .popover(isPresented: $isShowing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                message
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The same look wherever the ⓘ sits: a section header would
            // otherwise make it small, capitalized and gray. `Color.primary`
            // rather than `.primary`, which in a header means its gray.
            .textCase(nil)
            .foregroundStyle(Color.primary)
            // Explicit: inside a section header the default padding shrinks to nothing.
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(width: 300, alignment: .leading)
            // A bubble on iPhone too, rather than a full sheet.
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// A label followed by its ⓘ, for rows and section headers.
struct InfoLabel: View {
    let title: LocalizedStringKey
    let message: Text

    init(_ title: LocalizedStringKey, message: Text) {
        self.title = title
        self.message = message
    }

    init(_ title: LocalizedStringKey, message: String) {
        self.init(title, message: Text(message))
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            InfoButton(title, message: message)
        }
    }
}
