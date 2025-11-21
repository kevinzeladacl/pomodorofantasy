//
//  pomofantasyApp.swift
//  pomofantasy
//
//  Created by mri on 19-11-25.
//

import SwiftUI

@main
struct pomofantasyApp: App {
    @StateObject private var timerManager = TimerManager()

    var body: some Scene {
        MenuBarExtra {
            PomodoroView(manager: timerManager)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: timerManager.mode == .work ? "timer" : "cup.and.saucer.fill")
                Text(timerManager.timeString)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
