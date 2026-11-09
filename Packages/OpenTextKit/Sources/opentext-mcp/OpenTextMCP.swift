import Foundation
import MCP
import OpenTextKit

func toValue(_ any: Any) -> Value {
    guard let data = try? JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed]),
          let v = try? JSONDecoder().decode(Value.self, from: data) else { return .null }
    return v
}

func toAny(_ v: Value) -> Any {
    guard let data = try? JSONEncoder().encode(v),
          let o = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return NSNull() }
    return o
}

@main
struct OpenTextMCP {
    static func main() async throws {
        let server = Server(
            name: "opentext-mcp", version: "1.0.0",
            instructions: "OpenText: convert documents and images, extract text, create files, combine PDFs, lock and unlock files. All local.",
            capabilities: .init(tools: .init(listChanged: false)))

        let tools: [Tool] = OpenTextTools.toolDefinitions().map { d in
            Tool(name: d["name"] as? String ?? "", description: d["description"] as? String,
                 inputSchema: toValue(d["inputSchema"] ?? [:]))
        }

        await server.withMethodHandler(ListTools.self) { _ in .init(tools: tools) }
        await server.withMethodHandler(CallTool.self) { params in
            var args = [String: Any]()
            for (k, v) in params.arguments ?? [:] { args[k] = toAny(v) }
            do {
                let result = try OpenTextTools.call(params.name, args)
                let text = String(decoding: (try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data(), as: UTF8.self)
                return .init(content: [.text(text: text, annotations: nil, _meta: nil)], structuredContent: Optional<Value>.some(toValue(result)), isError: false)
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                return .init(content: [.text(text: msg, annotations: nil, _meta: nil)], isError: true)
            }
        }

        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }
}
