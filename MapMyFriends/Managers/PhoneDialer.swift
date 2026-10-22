//
//  PhoneDialer.swift
//  MapMyFriends
//

import Foundation

/// Turns a phone number as typed in Contacts into `tel:` and `sms:` URLs.
///
/// Stripping everything but digits ran an extension into the number ("555-1234 ext. 12"
/// dialed 555123412), dropped letters from vanity numbers, and kept non-Latin digits that no
/// phone link accepts.
enum PhoneDialer {

    /// Dials the main number, then the extension after a pause.
    static func callURL(for phone: String) -> URL? {
        guard let (main, ext) = parse(phone) else { return nil }
        let pause = ext.map { ",\($0)" } ?? ""
        return URL(string: "tel:\(main)\(pause)")
    }

    /// Texts the main number; an extension means nothing to Messages.
    static func messageURL(for phone: String) -> URL? {
        guard let (main, _) = parse(phone) else { return nil }
        return URL(string: "sms:\(main)")
    }

    // MARK: - Private

    /// Words and symbols that start an extension, longest first so "ext." wins over "x".
    private static let extensionMarkers = ["extension", "ext.", "ext", "x", "#", ";", ","]

    /// - Returns: The main number (ASCII digits, with a leading "+" if it had one) and the
    ///   extension's digits, or `nil` when there's nothing dialable.
    private static func parse(_ phone: String) -> (main: String, ext: String?)? {
        let lower = phone.lowercased()
        var mainPart = Substring(lower)
        var extPart: Substring?

        // The first marker that comes after at least one digit starts the extension;
        // "x" inside a vanity word like "1-800-XFINITY" isn't one because letters follow it.
        for marker in extensionMarkers {
            guard let range = lower.range(of: marker) else { continue }
            let before = lower[..<range.lowerBound]
            let after = lower[range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard before.contains(where: { asciiDigit($0) != nil }),
                  let first = after.first, asciiDigit(first) != nil else { continue }
            mainPart = before
            extPart = Substring(after)
            break
        }

        // Letters only count inside something that's already a number ("1-800-FLOWERS"),
        // or text like "n/a" would dial 62.
        guard mainPart.contains(where: { asciiDigit($0) != nil }) else { return nil }
        let main = dialable(mainPart, keepsLeadingPlus: true)
        let ext = extPart.map { dialable($0, keepsLeadingPlus: false) }.flatMap { $0.isEmpty ? nil : $0 }
        return (main, ext)
    }

    /// ASCII digits from any script, keypad digits for letters, and "+" only up front.
    private static func dialable(_ text: Substring, keepsLeadingPlus: Bool) -> String {
        var result = ""
        for character in text {
            if let digit = asciiDigit(character) {
                result.append(digit)
            } else if let keypad = keypadDigit(character) {
                result.append(keypad)
            } else if character == "+", keepsLeadingPlus, result.isEmpty {
                result.append("+")
            }
        }
        return result
    }

    /// "٣" → "3", "3" → "3"; anything that isn't a single decimal digit → nil.
    private static func asciiDigit(_ character: Character) -> Character? {
        guard character.isWholeNumber, let value = character.wholeNumberValue, (0...9).contains(value),
              character.unicodeScalars.count == 1,
              character.unicodeScalars.first?.properties.numericType == .decimal
        else { return nil }
        return Character(String(value))
    }

    private static let keypad: [Character: Character] = {
        let groups = ["abc": "2", "def": "3", "ghi": "4", "jkl": "5", "mno": "6", "pqrs": "7", "tuv": "8", "wxyz": "9"]
        var map: [Character: Character] = [:]
        for (letters, digit) in groups {
            for letter in letters { map[letter] = Character(digit) }
        }
        return map
    }()

    private static func keypadDigit(_ character: Character) -> Character? {
        keypad[Character(character.lowercased())]
    }
}
