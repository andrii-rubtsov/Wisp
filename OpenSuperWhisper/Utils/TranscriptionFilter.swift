import Foundation

enum TranscriptionFilter {
    /// Detects hallucinated or empty transcription results produced from silence.
    /// Whisper commonly outputs phrases like "Продолжение следует...", "Thank you.",
    /// "Thanks for watching!", subtitles attribution, etc. when there's no real speech.
    static func isEmptyOrHallucinated(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty or whitespace-only
        if trimmed.isEmpty { return true }

        // Strip all punctuation and whitespace, check if anything meaningful remains
        let stripped = trimmed.unicodeScalars.filter {
            !CharacterSet.punctuationCharacters.contains($0)
            && !CharacterSet.whitespacesAndNewlines.contains($0)
            && !CharacterSet.symbols.contains($0)
        }
        if stripped.isEmpty { return true }

        // Very short results (1-2 chars after stripping) are almost always hallucinations
        if String(stripped).count <= 2 { return true }

        // Common Whisper hallucination patterns on silence (language-independent)
        let lower = trimmed.lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hallucinations = [
            "продолжение следует",
            "thank you",
            "thanks for watching",
            "thanks for listening",
            "please subscribe",
            "like and subscribe",
            "subtitles by",
            "translated by",
            "copyright",
            "sous-titres",
            "untertitel",
            "sottotitoli",
            "you",
            "bye",
            "the end",
        ]
        for pattern in hallucinations {
            if lower == pattern { return true }
            // Also catch "Thank you for watching." etc.
            if lower.hasPrefix(pattern) && lower.count <= pattern.count + 15 { return true }
        }

        return false
    }
}
