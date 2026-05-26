//
//  AboutView.swift
//  MapMyFriends
//

import SwiftUI

struct AboutView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerSection
                cardsSection
            }
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .topTrailing) {
            dismissButton
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [Color.blue.opacity(0.08), Color.blue.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 280)

            VStack(spacing: 12) {
                // App icon
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.blue)
                            .shadow(color: .blue.opacity(0.3), radius: 12, y: 6)
                    )

                Text("Map My Friends")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.primary)

                Text("See your contacts on a map.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)
        }
    }

    // MARK: - Cards

    private var cardsSection: some View {
        VStack(spacing: 16) {
            aboutCard
            attributionCard
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 40)
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About the app")
                .font(.headline)

            Text("Map My Friends is an iOS app that reads your phone contacts, geocodes their addresses, and plots them as clustered pins on a full-screen map. Your location is shown as a blue dot. Tap a pin to see the contact's name and address type.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            Text("All geocoding results are cached locally so subsequent launches are near-instant — and it's built entirely with Apple frameworks, with no third-party dependencies.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private var attributionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Made by")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("mfyameen")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("❤️")
                    .font(.subheadline)
            }

            Text("Entirely open-source. Built with a little help from AI.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Link(destination: URL(string: "https://github.com/mfyameen/MapMyFriends")!) {
                Image("GitHubLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 28)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    // MARK: - Dismiss

    private var dismissButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

#Preview {
    AboutView()
}
