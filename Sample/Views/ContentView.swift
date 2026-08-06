//
//  ContentView.swift
//  Sample
//
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            ProductsView()
                .tabItem {
                    Label("Products", systemImage: "bag.fill")
                }

            EntitlementsView()
                .tabItem {
                    Label("Entitlements", systemImage: "checkmark.seal.fill")
                }

            MoreView()
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
        }
        .accentColor(.blue)
    }
}

// MARK: - Shared building blocks

/// The alert pair every screen shows. Kept in one place so a new screen cannot
/// silently swallow an error by forgetting to attach them.
struct MessageAlerts: ViewModifier {

    @EnvironmentObject var appState: AppState

    func body(content: Content) -> some View {
        content
            .alert("Error", isPresented: .constant(appState.errorMessage != nil)) {
                Button("OK") { appState.clearMessages() }
            } message: {
                Text(appState.errorMessage ?? "")
            }
            .alert("Success", isPresented: .constant(appState.successMessage != nil)) {
                Button("OK") { appState.clearMessages() }
            } message: {
                Text(appState.successMessage ?? "")
            }
    }
}

extension View {

    func messageAlerts() -> some View {
        return modifier(MessageAlerts())
    }
}

struct ActionButton: View {

    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(color)
                .cornerRadius(10)
        }
    }
}

struct LoadingOverlay: View {

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .padding(40)
                .background(Color(.systemGray5))
                .cornerRadius(16)
        }
    }
}

struct EmptyStateView: View {

    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DetailSection<Content: View>: View {

    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 0) {
                content
            }
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
}

struct DetailRow: View {

    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
        .padding()
    }
}

struct StatusBadge: View {

    let isActive: Bool

    var body: some View {
        Text(isActive ? "Active" : "Inactive")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.green : Color.red)
            .cornerRadius(8)
    }
}

/// Formats the dates the SDK hands back. Built once — a DateFormatter is
/// expensive enough that building one per row shows up in a long list.
let sampleDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short

    return formatter
}()

func formatDate(_ date: Date?) -> String {
    guard let date: Date = date else { return "N/A" }

    return sampleDateFormatter.string(from: date)
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
