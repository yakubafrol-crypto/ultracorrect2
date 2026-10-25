import SwiftUI

@main
struct UltraCorrectApp: App {
    var body: some Scene {
        MenuBarExtra("UltraCorrect", systemImage: "character.cursor.ibeam") {
            Text("UltraCorrect 2 — в разработке")
            Text("Механика ввода появится в 01c")
            Divider()
            Button("Выйти") { NSApplication.shared.terminate(nil) }
        }
    }
}
