//
//  WallpaperFreeApp.swift
//  WallpaperFree
//
//  Created by TAKAMURA on 25.12.2025.
//

import SwiftUI
import CoreData

@main
struct WallpaperFreeApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                //.environment(\.managedObjectContext, persistenceController.container.viewContext)
        }.windowResizability(.contentSize)
    }
}
