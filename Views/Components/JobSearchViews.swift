import SwiftUI

// MARK: - Job Search Field

/// Glass search field for the All Jobs tab.
struct JobSearchField: View {

    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 15

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: fontSize - 1, weight: .semibold))
                .foregroundColor(.white.opacity(isFocused.wrappedValue ? 0.7 : 0.35))
                .accessibilityHidden(true)

            TextField(
                "",
                text: $text,
                prompt: Text("Search title, company or skill").foregroundColor(.white.opacity(0.3))
            )
            .font(.system(size: fontSize))
            .foregroundColor(.white)
            .tint(AppTheme.violet)
            .focused(isFocused)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit(onSubmit)
            .accessibilityLabel("Search jobs")

            if !text.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: fontSize))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(minWidth: 28, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(isFocused.wrappedValue ? 0.08 : 0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isFocused.wrappedValue ? AppTheme.violet.opacity(0.55) : Color.white.opacity(0.09),
                    lineWidth: isFocused.wrappedValue ? 1 : 0.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { isFocused.wrappedValue = true }
        .animation(.easeOut(duration: 0.15), value: isFocused.wrappedValue)
    }
}

// MARK: - Suggestions

/// Shown while the search field is focused and empty.
struct JobSearchSuggestions: View {

    let recentSearches: [String]
    let onSelect: (String) -> Void
    let onRemoveRecent: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {

            if !recentSearches.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    sectionTitle("RECENT")

                    ForEach(recentSearches, id: \.self) { term in
                        HStack(spacing: 10) {
                            Button {
                                onSelect(term)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.3))
                                    Text(term)
                                        .font(.system(size: 15))
                                        .foregroundColor(.white.opacity(0.8))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .frame(minHeight: 40)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Search \(term)")

                            Button {
                                onRemoveRecent(term)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.3))
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(term) from recent searches")
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("TRY")
                SearchChips(terms: JobSearchViewModel.suggestions, onSelect: onSelect)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundColor(.white.opacity(0.3))
    }
}

// MARK: - Chips

struct SearchChips: View {

    let terms: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ChipFlowLayout(spacing: 8) {
            ForEach(terms, id: \.self) { term in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSelect(term)
                } label: {
                    Text(term)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.06))
                        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Flow Layout

/// Wraps chips onto as many lines as they need.
struct ChipFlowLayout: Layout {

    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews, width: bounds.width)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height)
                )
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width

            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }

            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }

        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
