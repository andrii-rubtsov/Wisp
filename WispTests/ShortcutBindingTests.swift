import XCTest
@testable import Wisp

final class ShortcutBindingTests: XCTestCase {

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let binding = ShortcutBinding(
            keyComboSlot: "binding-2",
            engine: "whisper",
            modelIdentifier: "ggml-large-v3-turbo.bin",
            modelDisplayName: "Turbo V3 large",
            initialPrompt: "transcribe clearly"
        )

        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(ShortcutBinding.self, from: data)

        XCTAssertEqual(decoded.id, binding.id)
        XCTAssertEqual(decoded.keyComboSlot, "binding-2")
        XCTAssertEqual(decoded.engine, "whisper")
        XCTAssertEqual(decoded.modelIdentifier, "ggml-large-v3-turbo.bin")
        XCTAssertEqual(decoded.modelDisplayName, "Turbo V3 large")
        XCTAssertEqual(decoded.initialPrompt, "transcribe clearly")
    }

    // MARK: - Backwards-compatible decoding (missing initialPrompt)

    func testDecodingWithoutInitialPrompt() throws {
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "keyComboSlot": "binding-0",
            "engine": "fluidaudio",
            "modelIdentifier": "v3",
            "modelDisplayName": "Parakeet v3"
        }
        """

        let data = json.data(using: .utf8)!
        let binding = try JSONDecoder().decode(ShortcutBinding.self, from: data)

        XCTAssertEqual(binding.initialPrompt, "")
        XCTAssertEqual(binding.engine, "fluidaudio")
        XCTAssertEqual(binding.modelIdentifier, "v3")
    }

    // MARK: - Slot management

    func testNextAvailableSlot_empty() {
        let slot = ShortcutBinding.nextAvailableSlot(excluding: [])
        XCTAssertEqual(slot, "binding-0")
    }

    func testNextAvailableSlot_firstTaken() {
        let existing = [ShortcutBinding(
            keyComboSlot: "binding-0",
            engine: "fluidaudio",
            modelIdentifier: "v3",
            modelDisplayName: "Parakeet v3"
        )]
        let slot = ShortcutBinding.nextAvailableSlot(excluding: existing)
        XCTAssertEqual(slot, "binding-1")
    }

    func testNextAvailableSlot_gapInMiddle() {
        let existing = [
            ShortcutBinding(keyComboSlot: "binding-0", engine: "a", modelIdentifier: "b", modelDisplayName: "c"),
            ShortcutBinding(keyComboSlot: "binding-2", engine: "a", modelIdentifier: "b", modelDisplayName: "c"),
        ]
        let slot = ShortcutBinding.nextAvailableSlot(excluding: existing)
        XCTAssertEqual(slot, "binding-1")
    }

    func testNextAvailableSlot_allTaken() {
        let existing = ShortcutBinding.slotNames.map {
            ShortcutBinding(keyComboSlot: $0, engine: "a", modelIdentifier: "b", modelDisplayName: "c")
        }
        let slot = ShortcutBinding.nextAvailableSlot(excluding: existing)
        XCTAssertEqual(slot, "binding-4", "Should return last slot when all taken")
    }

    // MARK: - Constants

    func testMaxBindings() {
        XCTAssertEqual(ShortcutBinding.maxBindings, 5)
    }

    func testSlotNamesCount() {
        XCTAssertEqual(ShortcutBinding.slotNames.count, ShortcutBinding.maxBindings)
    }

    func testSlotNamesFormat() {
        for (i, name) in ShortcutBinding.slotNames.enumerated() {
            XCTAssertEqual(name, "binding-\(i)")
        }
    }

    // MARK: - Equatable

    func testEquatable_same() {
        let id = UUID()
        let a = ShortcutBinding(id: id, keyComboSlot: "binding-0", engine: "whisper", modelIdentifier: "m", modelDisplayName: "M")
        let b = ShortcutBinding(id: id, keyComboSlot: "binding-0", engine: "whisper", modelIdentifier: "m", modelDisplayName: "M")
        XCTAssertEqual(a, b)
    }

    func testEquatable_differentEngine() {
        let id = UUID()
        let a = ShortcutBinding(id: id, keyComboSlot: "binding-0", engine: "whisper", modelIdentifier: "m", modelDisplayName: "M")
        let b = ShortcutBinding(id: id, keyComboSlot: "binding-0", engine: "fluidaudio", modelIdentifier: "m", modelDisplayName: "M")
        XCTAssertNotEqual(a, b)
    }
}
