//
//  InfoButton.swift
//  Dock Finder
//
//  The small blue ⓘ next to a label: tap it for a short explanation in a
//  popover, instead of a paragraph of fine print on the screen.
//

import SwiftUI
import UIKit

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
            InfoPopoverContent(title: Text(title), message: message)
                // A bubble on iPhone too, rather than a full sheet.
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// What every ⓘ bubble shows: a bold title and the explanation.
struct InfoPopoverContent: View {
    let title: Text
    let message: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            title
                .font(.headline)
            message
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textCase(nil)
        .foregroundStyle(Color.primary)
        .padding(16)
        .frame(width: 300, alignment: .leading)
    }
}

/// A label followed by its ⓘ, for list rows. Section headers use `InfoHeader`.
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

/// A section header title followed by its ⓘ. A SwiftUI popover opened
/// from a header inherits the header's layout and loses its padding, so
/// this one opens the same bubble through UIKit, with a fresh environment.
struct InfoHeader: View {
    let title: String
    let message: String

    init(_ title: String, message: String) {
        self.title = title
        self.message = message
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            HeaderInfoButton(title: title, message: message)
                .fixedSize()
        }
    }
}

private struct HeaderInfoButton: UIViewRepresentable {
    let title: String
    let message: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(
            UIImage(systemName: "info.circle", withConfiguration: UIImage.SymbolConfiguration(textStyle: .body)),
            for: .normal
        )
        let coordinator = context.coordinator
        button.addAction(UIAction { [weak button, weak coordinator] _ in
            guard let button else { return }
            coordinator?.present(from: button)
        }, for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.title = title
        context.coordinator.message = message
        button.accessibilityLabel = "About \(title)"
    }

    final class Coordinator: NSObject, UIPopoverPresentationControllerDelegate {
        var title = ""
        var message = ""

        func present(from button: UIButton) {
            guard var top = button.window?.rootViewController else { return }
            while let presented = top.presentedViewController { top = presented }
            let content = UIHostingController(rootView: InfoPopoverContent(title: Text(title), message: Text(message)))
            content.modalPresentationStyle = .popover
            content.preferredContentSize = content.sizeThatFits(in: CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
            content.view.backgroundColor = .clear
            if let popover = content.popoverPresentationController {
                popover.sourceView = button
                popover.sourceRect = button.bounds
                popover.delegate = self
            }
            top.present(content, animated: true)
        }

        /// A bubble on iPhone too, rather than a full sheet.
        func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
            .none
        }
    }
}
