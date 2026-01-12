//
//  MoreView.swift
//  Sample
//
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//

import SwiftUI
import Qonversion

struct MoreView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    NavigationLink(destination: RemoteConfigsView()) {
                        MenuRow(
                            icon: "gear",
                            title: "Remote Configs",
                            subtitle: "Remote configs & experiments",
                            color: .blue
                        )
                    }
                    
                    NavigationLink(destination: UserView()) {
                        MenuRow(
                            icon: "person.fill",
                            title: "User",
                            subtitle: "Identity, properties & attribution",
                            color: .green
                        )
                    }
                    
                    NavigationLink(destination: NoCodesView()) {
                        MenuRow(
                            icon: "doc.text.fill",
                            title: "No-Codes",
                            subtitle: "No-code screens & paywalls",
                            color: .purple
                        )
                    }
                    
                    NavigationLink(destination: OtherView()) {
                        MenuRow(
                            icon: "ellipsis.circle.fill",
                            title: "Other",
                            subtitle: "Additional SDK methods",
                            color: .orange
                        )
                    }
                }
                
                Section("SDK Info") {
                    if let userInfo = appState.userInfo {
                        HStack {
                            Text("Qonversion ID")
                            Spacer()
                            Text(userInfo.qonversionId)
                                .foregroundColor(.secondary)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
            .navigationTitle("More")
        }
    }
}

// MARK: - Menu Row
struct MenuRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(color)
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    MoreView()
        .environmentObject(AppState())
}
