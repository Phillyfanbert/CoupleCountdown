// JoinCodeGenerator.swift — 6-character pairing code generation (DESIGN.md §5.3 point 3)

import Foundation

public enum JoinCodeGenerator {
    /// Uppercase alphanumeric, excluding visually ambiguous characters
    /// (0/O, 1/I) per DESIGN.md §5.3 — 32^6 ≈ 1.07 billion combinations.
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    public static func generate(length: Int = 6) -> String {
        String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}
