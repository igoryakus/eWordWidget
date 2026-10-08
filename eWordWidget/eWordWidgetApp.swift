//
//  eWordWidgetApp.swift
//  eWordWidget
//
//  Created by igoryakus on 02/10/2026.
//

import SwiftUI

@main
struct eWordWidgetApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { _ in }
        }
        // Нажатие на виджет открывает окно, даже если приложение уже запущено в фоне (после озвучки) без окон.
        .handlesExternalEvents(matching: ["open"])
    }
}
