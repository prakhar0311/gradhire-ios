import SwiftUI

// MARK: - Jobs Filter Bar

/// Result count plus an optional sort menu, shared by the "For You" and
/// "All Jobs" tabs.
struct JobsFilterBar: View {

    var sort: Binding<JobSort>? = nil  // nil hides the sort menu (All Jobs has no scores)
    let resultCount: Int?

    var body: some View {
        HStack(spacing: 8) {

            if let resultCount {
                Text("\(resultCount) \(resultCount == 1 ? "job" : "jobs")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: resultCount)
            }

            Spacer(minLength: 4)

            if let sort {
                Menu {
                    Picker("Sort", selection: sort) {
                        ForEach(JobSort.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    FilterChip(
                        icon: "arrow.up.arrow.down",
                        title: sort.wrappedValue.title,
                        isActive: sort.wrappedValue != .bestMatch
                    )
                }
                .accessibilityLabel("Sort: \(sort.wrappedValue.title)")
            }
        }
        .frame(minHeight: 30)
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {

    let icon: String
    let title: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .opacity(0.6)
        }
        .foregroundColor(isActive ? .white : .white.opacity(0.55))
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background {
            if isActive {
                LinearGradient(
                    colors: [
                        AppTheme.purple.opacity(0.5),
                        AppTheme.teal.opacity(0.3)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                Color.white.opacity(0.05)
            }
        }
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(isActive ? 0.18 : 0.09), lineWidth: 0.5)
        )
        .clipShape(Capsule())
        // Badge dot marks a non-default choice
        .overlay(alignment: .topTrailing) {
            if isActive {
                Circle()
                    .fill(AppTheme.teal)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(AppTheme.base, lineWidth: 1.5))
                    .offset(x: 1, y: -1)
            }
        }
    }
}
