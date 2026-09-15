import Foundation

/// Shared transport helpers for LLM providers.
enum LLMTransport {
    static func throwIfHTTPError(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode >= 400 else { return }
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = root["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw LLMError.apiError(message)
        }
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = root["message"] as? String, !message.isEmpty {
            throw LLMError.apiError(message)
        }
        throw LLMError.apiError("HTTP \(http.statusCode)")
    }
}

extension URLSession {
    /// Parse an SSE byte stream, yielding the raw `data:` payload strings.
    func sseDataLines(for request: URLRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await self.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 4000 { break }
                        }
                        if let data = body.data(using: .utf8),
                           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let error = root["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            continuation.finish(throwing: LLMError.apiError(message))
                        } else {
                            continuation.finish(throwing: LLMError.apiError("HTTP \(http.statusCode)"))
                        }
                        return
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        if !payload.isEmpty { continuation.yield(payload) }
                    }
                    continuation.finish()
                } catch {
                    if error is CancellationError || (error as? URLError)?.code == .cancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: LLMError.networkError(error.localizedDescription))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

func mapSSEPayloads<T: Sendable>(
    _ payloads: AsyncThrowingStream<String, Error>,
    transform: @escaping @Sendable (Data) -> T?
) -> AsyncThrowingStream<T, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                for try await payload in payloads {
                    guard let data = payload.data(using: .utf8), let value = transform(data) else { continue }
                    continuation.yield(value)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
