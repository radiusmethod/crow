import SwiftUI
import CrowCore

/// Reusable token / chip editor bound to a `[String]`.
///
/// Existing values render as removable gold capsules (styled like ``LinkChip``);
/// a trailing text field adds new tokens. Tokens commit on Return, on a typed
/// comma, or when a comma-containing string is pasted and submitted. Input is
/// trimmed, empty entries are ignored, and exact duplicates (case-sensitive) are
/// dropped. Backspace in an empty field removes the last chip.
///
/// Chips + field wrap across lines via ``FlowLayout``. Binding directly to the
/// model's existing `[String]` means there is no persistence or schema change —
/// existing comma-separated configs already decode into the array.
public struct TokenListEditor: View {
    @Binding var tokens: [String]
    private let placeholder: String

    @State private var input: String = ""
    @FocusState private var fieldFocused: Bool

    /// - Parameters:
    ///   - tokens: The backing array of token strings.
    ///   - placeholder: Prompt shown in the input field when there are no tokens.
    public init(tokens: Binding<[String]>, placeholder: String = "Add…") {
        self._tokens = tokens
        self.placeholder = placeholder
    }

    public var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                chip(token, at: index)
            }
            inputField
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(CorveilTheme.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(CorveilTheme.borderSubtle, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { fieldFocused = true }
    }

    // MARK: Subviews

    private func chip(_ token: String, at index: Int) -> some View {
        HStack(spacing: 4) {
            Text(token)
                .font(.caption)
                .fontWeight(.medium)
            Button {
                remove(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(token)")
        }
        .foregroundStyle(CorveilTheme.gold)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(CorveilTheme.gold.opacity(0.1))
        .overlay(
            Capsule().strokeBorder(CorveilTheme.goldDark.opacity(0.3), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    private var inputField: some View {
        TextField(tokens.isEmpty ? placeholder : "", text: $input)
            .textFieldStyle(.plain)
            .font(.caption)
            .autocorrectionDisabled()
            .frame(minWidth: 80)
            .focused($fieldFocused)
            .onSubmit { commit() }
            .onExitCommand { fieldFocused = false }
            // Catch a typed comma immediately; a paste of "a, b, c" carries no key
            // event, so its commas are split in commit() on Return instead.
            .onKeyPress(",") {
                commit()
                return .handled
            }
            // TextField doesn't report a backspace when already empty (no text
            // change), so use onKeyPress to remove the last chip in that case.
            .onKeyPress(.delete) {
                if input.isEmpty, !tokens.isEmpty {
                    tokens.removeLast()
                    return .handled
                }
                return .ignored
            }
    }

    // MARK: Mutation

    private func commit() {
        tokens = Self.adding(input, to: tokens)
        input = ""
    }

    private func remove(at index: Int) {
        guard tokens.indices.contains(index) else { return }
        tokens.remove(at: index)
    }

    // MARK: Pure logic (unit-tested)

    /// Splits `input` on commas, trims whitespace, drops empties, and appends to
    /// `existing`, skipping case-sensitive exact duplicates (against both the
    /// existing array and tokens added earlier in the same call). Pure — never
    /// mutates its arguments.
    ///
    /// `nonisolated` so the (main-actor-isolated, via `View`) type's helper stays
    /// callable from synchronous nonisolated contexts such as the test suite.
    nonisolated static func adding(_ input: String, to existing: [String]) -> [String] {
        var result = existing
        for piece in input.split(separator: ",", omittingEmptySubsequences: true) {
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard !result.contains(trimmed) else { continue }
            result.append(trimmed)
        }
        return result
    }
}

// MARK: - FlowLayout

/// Wrapping flow layout: lays subviews left-to-right, wrapping to a new line when
/// the next subview would overflow the proposed width. macOS 14+ `Layout`.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + lineSpacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)

        return CGSize(width: proposal.width ?? totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#if DEBUG
private struct TokenListEditorPreviewHost: View {
    @State private var repos = ["zarf-dev/*", "bmlt-enabled/yap", "radiusmethod/crow"]
    @State private var empty: [String] = []

    var body: some View {
        Form {
            Section("With values") {
                TokenListEditor(tokens: $repos, placeholder: "owner/repo")
            }
            Section("Empty") {
                TokenListEditor(tokens: $empty, placeholder: "Add a label")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 360)
    }
}

#Preview("TokenListEditor") {
    TokenListEditorPreviewHost()
        .environment(\.colorScheme, .dark)
}
#endif
