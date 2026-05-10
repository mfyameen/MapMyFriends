//
//  NoDataExfiltrationTests.swift
//  MapMyFriendsTests
//
//  Static analysis tests that scan app source files for network calls,
//  third-party URLs, or other data exfiltration vectors.
//

import Foundation
import Testing

struct NoDataExfiltrationTests {

    // Patterns that indicate outbound network usage beyond Apple-provided SDK calls
    private static let forbiddenPatterns: [(label: String, pattern: String)] = [
        ("URLSession usage", "URLSession"),
        ("URLRequest construction", "URLRequest"),
        ("URL connection", "NSURLConnection"),
        ("URL loading", "NSURLSession"),
        ("Hardcoded http:// URL", "http://"),
        ("Hardcoded https:// URL", "https://"),
        ("WebSocket usage", "URLSessionWebSocketTask"),
        ("WKWebView loading", "WKWebView"),
        ("UIWebView loading", "UIWebView"),
        ("Socket usage", "CFSocket"),
        ("Stream usage", "NSStream"),
        ("Network framework", "import Network"),
        ("Alamofire dependency", "import Alamofire"),
        ("Firebase dependency", "import Firebase"),
        ("Analytics SDK", "import Analytics"),
        ("Amplitude SDK", "import Amplitude"),
        ("Mixpanel SDK", "import Mixpanel"),
        ("Sentry SDK", "import Sentry"),
    ]

    /// Returns all `.swift` files under the main app target (excluding tests).
    private static func appSourceFiles() throws -> [URL] {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MapMyFriendsTests/
            .deletingLastPathComponent()  // project root
        let appDir = projectRoot.appendingPathComponent("MapMyFriends")

        let enumerator = FileManager.default.enumerator(
            at: appDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var swiftFiles: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" {
                swiftFiles.append(url)
            }
        }
        return swiftFiles
    }

    @Test func noForbiddenNetworkPatterns() throws {
        let files = try NoDataExfiltrationTests.appSourceFiles()
        #expect(!files.isEmpty, "Should find at least one Swift source file")

        var violations: [String] = []

        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let fileName = file.lastPathComponent

            for (label, pattern) in NoDataExfiltrationTests.forbiddenPatterns {
                if contents.contains(pattern) {
                    violations.append("\(fileName): \(label) (\"\(pattern)\")")
                }
            }
        }

        #expect(violations.isEmpty,
            "Found potential data exfiltration vectors:\n\(violations.joined(separator: "\n"))")
    }

    @Test func noInfoPlistExportsOrCustomSchemes() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appDir = projectRoot.appendingPathComponent("MapMyFriends")

        let enumerator = FileManager.default.enumerator(
            at: appDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "plist" else { continue }

            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? ""
            let fileName = url.lastPathComponent

            #expect(!text.contains("NSAppTransportSecurity"),
                "\(fileName) disables App Transport Security — review required")
            #expect(!text.contains("NSAllowsArbitraryLoads"),
                "\(fileName) allows arbitrary network loads — review required")
        }
    }

    @Test func noEmbeddedAPIKeysOrSecrets() throws {
        let secretPatterns: [(label: String, pattern: String)] = [
            ("API key assignment", "apiKey"),
            ("API key assignment", "api_key"),
            ("Secret assignment", "secret"),
            ("Token assignment", "token"),
            ("Authorization header", "Authorization"),
            ("Bearer token", "Bearer "),
        ]

        let files = try NoDataExfiltrationTests.appSourceFiles()
        var violations: [String] = []

        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let fileName = file.lastPathComponent

            for (label, pattern) in secretPatterns {
                // Look for string literal assignments containing these patterns
                let lines = contents.components(separatedBy: .newlines)
                for (lineNum, line) in lines.enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    // Skip comments
                    if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { continue }

                    if line.contains(pattern) && line.contains("\"") {
                        violations.append("\(fileName):\(lineNum + 1): possible \(label)")
                    }
                }
            }
        }

        #expect(violations.isEmpty,
            "Found possible embedded secrets:\n\(violations.joined(separator: "\n"))")
    }
}
