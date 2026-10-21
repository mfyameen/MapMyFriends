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
                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)

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

            Text("Map My Friends shows your friends, family, and colleagues nearby and around the world. Your contacts' addresses (not their real-time location) are pinned on the map — making it easy to see who's near you, whether you're traveling for work or exploring a new neighborhood.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            Text("Your contacts never leave your device except for their addresses, which are sent only to Apple Maps to find their location. Results are cached on your device, and nothing is sent to us or any third party. The app is built entirely with Apple frameworks, and the code is open-source on GitHub.")
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

            Text("© 2026 Rosedale Co")
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
