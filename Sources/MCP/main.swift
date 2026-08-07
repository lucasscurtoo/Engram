import Foundation

// MCP stdio transport: newline-delimited JSON-RPC on stdin/stdout, logs to stderr.

func log(_ message: String) {
    FileHandle.standardError.write(Data("[engram-mcp] \(message)\n".utf8))
}

let server: EngramMCPServer
do {
    server = try EngramMCPServer()
} catch {
    log("failed to open store: \(error.localizedDescription)")
    exit(1)
}

log("ready (store opened)")

while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty else { continue }
    guard let data = line.data(using: .utf8),
          let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        log("skipping unparseable line")
        continue
    }
    guard let responseObject = await server.handle(message) else { continue }
    let responseData = try JSONSerialization.data(withJSONObject: responseObject)
    FileHandle.standardOutput.write(responseData)
    FileHandle.standardOutput.write(Data("\n".utf8))
}
