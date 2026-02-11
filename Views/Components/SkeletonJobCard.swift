import SwiftUI

struct SkeletonJobCard: View {

    var body: some View {
        HStack(spacing: 16) {

            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 10) {

                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 16)
                    .frame(maxWidth: 180)

                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.25))
                    .frame(height: 14)
                    .frame(maxWidth: 120)

                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 12)
                    .frame(maxWidth: 90)
            }

            Spacer()
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.3))
        )
        .redacted(reason: .placeholder)
       
    }
}

