//
//  ContentView.swift
//  Sample
//
//  Copyright © 2024 Qonversion Inc. All rights reserved.
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
            
            OfferingsView()
                .tabItem {
                    Label("Offerings", systemImage: "gift.fill")
                }
            
            MoreView()
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
        }
        .accentColor(.blue)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
