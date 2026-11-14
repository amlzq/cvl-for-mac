//
//  ChineseVariantsLinterApp.swift
//  ChineseVariantsLinter
//
//  Created by Zeaon on 11/13/26.
//

import SwiftUI

@main
struct ChineseVariantsLinterApp: App {
    var body: some Scene {
        MenuBarExtra("Chinese Variants Linter", systemImage: "character.book.closed") {
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
