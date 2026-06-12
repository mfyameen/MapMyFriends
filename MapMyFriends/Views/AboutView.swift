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

            Text("Map My Friends shows your friends, family, and colleagues nearby and around the world. Your contacts addesses (not real-time location) are pinned on the map - making it easy to see who's near you whethere you're traveling for work or exploring a new neighbourhood.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            Text("All data is stored locally and never uploaded anywhere — and it's built entirely with Apple frameworks, with no third-party dependencies. The code is completely open-source and available on GitHub.")
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
