//
//  SagevoxApp.swift
//  Sagevox
//
//  Created by Mike B on 1/7/26.
//

import SwiftUI
import SwiftData

@main
struct SagevoxApp: App {
    // Services and ViewModels
    @StateObject private var audioPlayer = AudioPlayerService()
    @StateObject private var libraryViewModel = LibraryViewModel()

    init() {
        Analytics.configure()
    }
    
    /*
    // SwiftData container - Disabled until models are migrated
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            // Add SwiftData models here later (e.g., ReadingProgress.self)
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    */

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioPlayer)
                .environmentObject(libraryViewModel)
        }
        //.modelContainer(sharedModelContainer)
    }
}
