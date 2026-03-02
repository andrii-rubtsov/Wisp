import Foundation
import AVFoundation

protocol TranscriptionEngine: AnyObject {
    var isModelLoaded: Bool { get }
    var engineName: String { get }
    var onProgressUpdate: ((Float) -> Void)? { get set }

    func initialize() async throws
    func transcribeAudio(url: URL) async throws -> String
    func cancelTranscription()
    func getSupportedLanguages() -> [String]
}

