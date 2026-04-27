// DemoTraceUploader.swift
// v0.4.6.3 / build 26
//
// Posts a finalized DemoTraceLogger payload to a tiny Cloudflare Worker
// endpoint, which in turn opens a GitHub Issue on voltra-live-ios with the
// trace inline. The Worker holds the GitHub PAT — we deliberately do NOT
// embed any credentials in the iOS binary (TestFlight binaries are
// extractable with publicly-available tools, and a leaked PAT scoped to
// this repo would let an attacker open arbitrary issues / spam the repo).
//
// Worker contract (see worker/voltra-trace-relay/index.js):
//
//   POST <endpoint>/trace
//   Headers:
//     X-Voltra-Trace-Token: <shared secret, baked into binary>
//     Content-Type: application/json
//   Body:
//     {
//       "header": { ...DemoTraceLogger.Header... },
//       "records": [...],
//       "userNote": "free-form text from the upload sheet, optional"
//     }
//   Response 200:
//     { "ok": true, "issueUrl": "https://github.com/.../issues/123" }
//
// The shared secret here is rate-limit / spam-prevention only; it doesn't
// gate access to anything sensitive. The Worker's GitHub PAT is the real
// security boundary and lives only in the Worker's environment vars.

import Foundation

@MainActor
final class DemoTraceUploader: ObservableObject {

    enum UploadError: Error, LocalizedError {
        case configMissing
        case encodingFailed
        case network(URLError)
        case server(status: Int, body: String)
        case decoding

        var errorDescription: String? {
            switch self {
            case .configMissing:
                return "Trace upload endpoint not configured in this build."
            case .encodingFailed:
                return "Could not encode the trace JSON."
            case .network(let e):
                return "Network error: \(e.localizedDescription)"
            case .server(let status, let body):
                return "Server returned \(status): \(body.prefix(200))"
            case .decoding:
                return "Server response was not valid JSON."
            }
        }
    }

    @Published var inFlight: Bool = false
    @Published var lastIssueURL: URL? = nil
    @Published var lastError: String? = nil

    /// Upload a finalized trace. The user can attach a free-form `note`
    /// (e.g. "drop-set didn't cancel when I held the tile").
    func upload(_ trace: DemoTraceLogger, note: String) async {
        inFlight = true
        defer { inFlight = false }
        lastError = nil

        do {
            let url = try Self.endpointURL()
            let token = Self.sharedToken()

            // Build request body. We attach the user note INSIDE the JSON
            // payload so the Worker can put it at the top of the issue body
            // for context.
            guard let traceData = trace.encodedJSON(),
                  let traceObj = try? JSONSerialization.jsonObject(with: traceData) as? [String: Any] else {
                throw UploadError.encodingFailed
            }
            var body: [String: Any] = traceObj
            if !note.isEmpty {
                body["userNote"] = note
            }
            let bodyData = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(token, forHTTPHeaderField: "X-Voltra-Trace-Token")
            req.httpBody = bodyData
            req.timeoutInterval = 30

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw UploadError.server(status: -1, body: "no HTTPURLResponse")
            }
            if http.statusCode != 200 {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                throw UploadError.server(status: http.statusCode, body: bodyStr)
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let urlStr = json["issueUrl"] as? String,
                  let issueURL = URL(string: urlStr) else {
                throw UploadError.decoding
            }
            self.lastIssueURL = issueURL
        } catch let e as UploadError {
            self.lastError = e.errorDescription
        } catch let e as URLError {
            self.lastError = UploadError.network(e).errorDescription
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    // MARK: - Build-time configuration
    //
    // The endpoint URL and shared token are read from Info.plist keys that
    // the release.yml workflow injects. If the keys are missing (e.g. dev
    // builds), upload becomes a no-op with a clear error.

    private static func endpointURL() throws -> URL {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "DemoTraceEndpoint") as? String,
              !raw.isEmpty,
              let url = URL(string: raw) else {
            throw UploadError.configMissing
        }
        return url
    }

    private static func sharedToken() -> String {
        // Empty string is a valid response — the Worker accepts unauthenticated
        // requests in dev and rejects them in prod. A consistent header is
        // always sent so the Worker can rate-limit on it.
        (Bundle.main.object(forInfoDictionaryKey: "DemoTraceSharedToken") as? String) ?? ""
    }
}
