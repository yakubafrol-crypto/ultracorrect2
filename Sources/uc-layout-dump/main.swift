import Carbon
import Foundation
import UCCore

// All TIS calls and UCKeyTranslate run synchronously on the main thread.
let requested = ["com.apple.keylayout.ABC": "en", "com.apple.keylayout.US": "us",
                 "com.apple.keylayout.Russian": "ru", "com.apple.keylayout.RussianWin": "ru-pc"]
let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Tests/Fixtures/layouts")
do {
    guard Thread.isMainThread else { throw CoreError.invalidData }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let sources = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
    var captured = Set<String>()
    for source in sources {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
        let systemID = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        guard let id = requested[systemID], let dataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { continue }
        let data = Unmanaged<CFData>.fromOpaque(dataPtr).takeUnretainedValue()
        let layout = UnsafeRawPointer(CFDataGetBytePtr(data)!).assumingMemoryBound(to: UCKeyboardLayout.self)
        let enabled = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled).map {
            CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque($0).takeUnretainedValue())
        } ?? false
        var entries: [LayoutEntry] = []
        for key in 0..<128 {
            for flags in 0..<4 {
                let carbonFlags = (flags & 1 != 0 ? shiftKey : 0) | (flags & 2 != 0 ? optionKey : 0)
                var dead: UInt32 = 0; var length = 0; var chars = [UniChar](repeating: 0, count: 16)
                let status = UCKeyTranslate(layout, UInt16(key), UInt16(kUCKeyActionDown), UInt32(carbonFlags >> 8),
                                            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead,
                                            chars.count, &length, &chars)
                if status == noErr && length > 0 {
                    entries.append(LayoutEntry(keyCode: key, modifiers: flags, text: String(utf16CodeUnits: chars, count: length), dead: dead != 0))
                }
            }
        }
        let table = LayoutTable(id: id, systemID: systemID, enabled: enabled, keyboardType: Int(LMGetKbdType()), entries: entries)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(table).write(to: directory.appendingPathComponent(id + ".json"), options: .atomic)
        captured.insert(systemID)
        print("layout=\(id) entries=\(entries.count) enabled=\(enabled)")
    }
    for systemID in requested.keys.sorted() where !captured.contains(systemID) { print("missing_layout=\(systemID)") }
    if captured.count != requested.count { exit(2) }
} catch { fputs("layout_dump_failed\n", stderr); exit(1) }
