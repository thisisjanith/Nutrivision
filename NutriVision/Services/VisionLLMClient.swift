//
//  VisionLLMClient.swift
//  NutriVision
//
//  Sends a captured frame to the vision-LLM proxy and decodes the structured
//  estimate. The proxy (Proxy/worker.js) owns the model API key and the prompt
//  + JSON schema, so both can change without an app release.
//

import Foundation

nonisolated enum VisionLLMError: Error, Equatable {
    case notConfigured
    case badStatus(Int)
    case malformedResponse
}

nonisolated struct EstimateContext: Sendable, Equatable {
    /// Camera-to-subject distance from the LiDAR depth sensor, when available.
    /// The model uses it with visible references (plate, fork) to judge size.
    var distanceMeters: Double?
}

protocol VisionLLMClient: Sendable {
    func estimate(jpeg: Data, context: EstimateContext) async throws -> CloudFoodEstimate
}

nonisolated struct ProxyVisionClient: VisionLLMClient {
    let endpoint: URL
    var token: String = AppConfig.proxyToken
    var session: URLSession = .shared

    /// nil when no proxy is configured, so callers can skip the cloud path.
    static func makeDefault() -> ProxyVisionClient? {
        AppConfig.proxyURL.map { ProxyVisionClient(endpoint: $0) }
    }

    func estimate(jpeg: Data, context: EstimateContext) async throws -> CloudFoodEstimate {
        let body = try Self.requestBody(jpeg: jpeg, context: context)
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { request.setValue(token, forHTTPHeaderField: "X-App-Token") }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else { throw VisionLLMError.badStatus(http.statusCode) }
        return try CloudFoodEstimate.decode(from: data)
    }

    static func requestBody(jpeg: Data, context: EstimateContext) throws -> Data {
        var payload: [String: Any] = [
            "image_base64": jpeg.base64EncodedString(),
            "media_type": "image/jpeg",
        ]
        if let distance = context.distanceMeters { payload["distance_m"] = (distance * 100).rounded() / 100 }
        return try JSONSerialization.data(withJSONObject: payload)
    }
}
