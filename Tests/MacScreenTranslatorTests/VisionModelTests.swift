import AppKit
import XCTest
@testable import MacScreenTranslator

final class VisionModelTests: XCTestCase {
    @MainActor
    func testCloudRecognitionUsesImageRequestAndParsesResponseWithoutNetwork() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VisionResponseProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
                                bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let text = try await ImageRecognition.recognize(context.makeImage()!, configuration: .model(
            .init(baseURL: "https://vision-test.invalid/v1", model: "test-vision", apiKey: "test")), session: session)
        XCTAssertEqual(text, "cloud recognized text")
    }

    func testBuildsMultimodalRequestWithImageAndIndependentModel() throws {
        let png = Data([1, 2, 3])
        let request = try ImageRecognition.makeRequest(png: png, settings: .init(baseURL: "https://example.com/v1/", model: "vision-model", apiKey: "test"))
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "vision-model")
        let messages = body["messages"] as! [[String: Any]]
        let parts = messages[0]["content"] as! [[String: Any]]
        XCTAssertEqual(parts[0]["type"] as? String, "text")
        let image = parts[1]["image_url"] as! [String: String]
        XCTAssertEqual(image["url"], "data:image/png;base64,\(png.base64EncodedString())")
    }

    func testRejectsMissingKeyModelInvalidEndpointAndOversizeImage() {
        let invalid: [VisionModelSettings] = [
            .init(baseURL: "https://example.com/v1", model: "vision", apiKey: ""),
            .init(baseURL: "https://example.com/v1", model: " ", apiKey: "test"),
            .init(baseURL: "file:///tmp", model: "vision", apiKey: "test"),
            .init(baseURL: "http://example.com/v1", model: "vision", apiKey: "test"),
            .init(baseURL: "https://example.com/v1?key=secret", model: "vision", apiKey: "test")
        ]
        for settings in invalid { XCTAssertThrowsError(try ImageRecognition.makeRequest(png: Data([1]), settings: settings)) }
        let settings = VisionModelSettings(baseURL: "http://localhost:1234/v1", model: "vision", apiKey: "test")
        XCTAssertNoThrow(try ImageRecognition.makeRequest(png: Data([1]), settings: settings))
        XCTAssertThrowsError(try ImageRecognition.makeRequest(png: Data(), settings: settings))
        XCTAssertThrowsError(try ImageRecognition.makeRequest(png: Data(repeating: 0, count: 20 * 1024 * 1024 + 1), settings: settings))
    }

    func testParsesTextAndRejectsErrorMalformedResponses() throws {
        let valid = Data(#"{"choices":[{"message":{"content":"  original text\n"}}]}"#.utf8)
        XCTAssertEqual(try ImageRecognition.parseResponse(valid, statusCode: 200), "original text")
        for status in [400, 401, 403, 404, 422, 429, 500] {
            XCTAssertThrowsError(try ImageRecognition.parseResponse(valid, statusCode: status))
        }
        for body in ["{}", "invalid", #"{"error":{"message":"bad"}}"#] {
            XCTAssertThrowsError(try ImageRecognition.parseResponse(Data(body.utf8), statusCode: 200))
        }
    }
}

private final class VisionResponseProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "vision-test.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"choices":[{"message":{"content":"cloud recognized text"}}]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
