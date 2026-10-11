import XCTest
@testable import LucidDiskCore

final class MCPSetupTests: XCTestCase {
    func testCopiedCommandsPreservePathsAsSingleLiteralArguments() throws {
        let projectPath = "/Users/example/John's projects/$(printf expanded)/mcp"
        let uvPath = "/Users/example/Tools with spaces/uv"
        let setup = MCPSetup(projectPath: projectPath, uvPath: uvPath)
        let expected = ["mcp", "add", "luciddisk", "--", uvPath, "run", "--project", projectPath, "luciddisk-mcp"]

        XCTAssertEqual(try capturedArguments(for: setup.codexCommand, executable: "codex"), expected)
        XCTAssertEqual(try capturedArguments(for: setup.claudeCodeCommand, executable: "claude"), expected)
    }

    func testDesktopConfigurationPreservesSpecialCharacters() throws {
        let path = "/Users/example/A \"quoted\" folder/John's mcp"
        let setup = MCPSetup(projectPath: path, uvPath: "/opt/homebrew/bin/uv")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(setup.claudeDesktopJSON.utf8)) as? [String: Any])
        let servers = try XCTUnwrap(object["mcpServers"] as? [String: [String: Any]])
        let server = try XCTUnwrap(servers["luciddisk"])

        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(server["command"] as? String, "/opt/homebrew/bin/uv")
        XCTAssertEqual(server["args"] as? [String], ["run", "--project", path, "luciddisk-mcp"])
    }

    /// A shell function captures arguments without starting an assistant or server.
    private func capturedArguments(for command: String, executable: String) throws -> [String] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "\(executable)() { printf '%s\\0' \"$@\"; }; \(command)"]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init)
    }
}
