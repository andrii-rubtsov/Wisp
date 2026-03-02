import XCTest
@testable import Wisp

final class TranscriptionErrorTests: XCTestCase {

    func testContextInitializationFailed_description() {
        let error = TranscriptionError.contextInitializationFailed
        XCTAssertEqual(error.errorDescription, "Failed to initialize transcription context")
    }

    func testAudioConversionFailed_description() {
        let error = TranscriptionError.audioConversionFailed
        XCTAssertEqual(error.errorDescription, "Failed to convert audio to PCM format")
    }

    func testProcessingFailed_noUnderlying() {
        let error = TranscriptionError.processingFailed()
        XCTAssertEqual(error.errorDescription, "Transcription processing failed")
    }

    func testProcessingFailed_withUnderlying() {
        let underlying = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "disk full"])
        let error = TranscriptionError.processingFailed(underlying)
        XCTAssertTrue(error.errorDescription!.contains("disk full"))
    }

    func testProcessingFailed_conformsToLocalizedError() {
        let error: LocalizedError = TranscriptionError.processingFailed()
        XCTAssertNotNil(error.errorDescription)
    }
}
