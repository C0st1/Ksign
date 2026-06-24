//
//  SuggestedSourceRow.swift
//  Ksign
//
//  Created by Nagata Asami on 25.06.2025.
//

import SwiftUI
import NukeUI
import NimbleViews

// MARK: - Row
struct SuggestedSourceRow: View {
    let suggestion: SuggestedSourcesViewModel.SuggestedSource
    let onAdd: () -> Void

    // MARK: Body
    var body: some View {
        HStack(spacing: 12) {
            _icon
            _text
            Spacer(minLength: 8)
            _trailing
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    // MARK: Subviews
    @ViewBuilder
    private var _icon: some View {
        if let iconURL = suggestion.iconURL {
            LazyImage(url: iconURL) { state in
                if let image = state.image {
                    image.appIconStyle()
                } else {
                    _placeholderIcon
                }
            }
        } else if suggestion.isLoading {
            _loadingIcon
        } else {
            _placeholderIcon
        }
    }

    private var _loadingIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 30, height: 30)
            ProgressView()
                .controlSize(.small)
        }
    }

    private var _placeholderIcon: some View {
        Image("App_Unknown")
            .appIconStyle()
    }

    private var _text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(suggestion.name)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(suggestion.url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var _trailing: some View {
        if suggestion.isAdded {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .accessibilityLabel(.localized("Added"))
        } else {
            Button {
                onAdd()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(.localized("Add"))
        }
    }
}
