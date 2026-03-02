import XCTest
@testable import Wisp

final class TranscriptionFilterTests: XCTestCase {

    // MARK: - Empty / Whitespace

    func testEmpty() {
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated(""))
    }

    func testWhitespaceOnly() {
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("   "))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("\t\n"))
    }

    // MARK: - Punctuation-only

    func testPunctuationOnly() {
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("..."))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("!!!"))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("?!."))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("—"))
    }

    // MARK: - Very short text (<=2 meaningful chars)

    func testSingleCharacter() {
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("a"))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("X."))
    }

    func testTwoCharacters() {
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("ok"))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("hi"))
    }

    func testThreeCharacters_notFiltered() {
        XCTAssertFalse(TranscriptionFilter.isEmptyOrHallucinated("hey"))
        XCTAssertFalse(TranscriptionFilter.isEmptyOrHallucinated("cat"))
    }

    // MARK: - Known hallucination patterns

    func testRussianHallucination() {
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("Продолжение следует..."))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("продолжение следует"))
    }

    func testEnglishHallucinations() {
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("Thank you."))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("Thank you for watching."))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("Thanks for watching!"))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("Thanks for listening."))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("Please subscribe."))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("Like and subscribe"))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("The end."))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("Bye."))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("you"))
    }

    func testSubtitleAttributions() {
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("Subtitles by"))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("Subtitles by Amara"))
        // Long suffix exceeds 15-char tolerance, so not filtered
        XCTAssertFalse(TranscriptionFilter.isEmptyOrHallucinated("Subtitles by the Amara.org community"))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("Translated by"))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("Copyright"))
    }

    func testFrenchGermanHallucinations() {
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("Sous-titres"))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("Untertitel"))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("Sottotitoli"))
    }

    // MARK: - Prefix matching with short suffix

    func testHallucinationPrefixWithShortSuffix() {
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("Thank you very much."))
    }

    func testHallucinationPrefixWithLongSuffix_notFiltered() {
        // "thank you" prefix + more than 15 extra chars should NOT be filtered
        XCTAssertFalse(TranscriptionFilter.isEmptyOrHallucinated("Thank you for your amazing contribution to the project"))
    }

    // MARK: - Valid transcription text

    func testValidShortSentence() {
        XCTAssertFalse(TranscriptionFilter.isEmptyOrHallucinated("Hello world"))
    }

    func testValidLongSentence() {
        XCTAssertFalse(TranscriptionFilter.isEmptyOrHallucinated("The quick brown fox jumps over the lazy dog"))
    }

    func testValidRussianText() {
        XCTAssertFalse(TranscriptionFilter.isEmptyOrHallucinated("Привет, как дела?"))
    }

    func testValidCodeText() {
        XCTAssertFalse(TranscriptionFilter.isEmptyOrHallucinated("func main() { print(\"hello\") }"))
    }

    // MARK: - Edge cases

    func testSymbolsOnly() {
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("♪ ♫"))
    }

    func testMixedPunctuationAndShortText() {
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("... a ..."))
    }

    func testCaseInsensitivity() {
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("THANK YOU."))
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("ThAnK yOu"))
    }

    func testLeadingTrailingWhitespace() {
        XCTAssertTrue(TranscriptionFilter.isEmptyOrHallucinated("  Thank you.  "))
        XCTAssertFalse(TranscriptionFilter.isEmptyOrHallucinated("  Hello world  "))
    }
}
