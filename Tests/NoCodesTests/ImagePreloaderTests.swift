//
//  ImagePreloaderTests.swift
//  NoCodesTests
//
//  Image extraction, inlining and the download deadline. All traffic is served
//  by a stub URL protocol, so the tests never touch the network.
//

import XCTest
@testable import NoCodes

/// A canned response for one URL. `hangs` never answers at all, which is what
/// makes the preloader's own deadline observable.
private struct StubbedResource {
    let data: Data
    let statusCode: Int
    let contentType: String?
    let hangs: Bool
}

private final class StubResourceRegistry: @unchecked Sendable {

    private let lock = NSLock()
    private var resources: [String: StubbedResource] = [:]
    private var requestedUrls: [String] = []

    var requestedUrlsCount: Int {
        lock.lock()
        defer { lock.unlock() }

        return requestedUrls.count
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        resources = [:]
        requestedUrls = []
    }

    func register(url: String, resource: StubbedResource) {
        lock.lock()
        defer { lock.unlock() }

        resources[url] = resource
    }

    func resource(for url: String) -> StubbedResource? {
        lock.lock()
        defer { lock.unlock() }

        requestedUrls.append(url)

        return resources[url]
    }
}

private final class StubURLProtocol: URLProtocol {

    static let registry = StubResourceRegistry()

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let url = request.url else { return }

        let resource: StubbedResource? = StubURLProtocol.registry.resource(for: url.absoluteString)
        guard let resource else {
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist, userInfo: nil)
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        // A hanging resource answers nothing at all: the request stays open
        // until the preloader abandons it.
        guard !resource.hangs else { return }

        var headerFields: [String: String] = [:]
        if let contentType = resource.contentType {
            headerFields["Content-Type"] = contentType
        }
        let response = HTTPURLResponse(url: url, statusCode: resource.statusCode, httpVersion: nil, headerFields: headerFields)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: resource.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
    }
}

/// URLResponse fills a missing MIME type in with "application/octet-stream",
/// so the silent-server case needs an explicit double.
private final class SilentMimeTypeResponse: URLResponse, @unchecked Sendable {

    private let stubbedMimeType: String?

    init(url: URL, mimeType: String?) {
        stubbedMimeType = mimeType
        super.init(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
    }

    required init?(coder: NSCoder) {
        stubbedMimeType = nil
        super.init(coder: coder)
    }

    override var mimeType: String? {
        return stubbedMimeType
    }
}

final class ImagePreloaderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.registry.reset()
    }

    // MARK: - Extraction

    func testImageTagSourcesAreInlined() async throws {
        let url = "https://cdn.qonversion.io/hero.png"
        register(url: url, bytes: pngBytes, contentType: "image/png")
        let preloader: ImagePreloader = makePreloader()
        let html = "<html><body><img src=\"\(url)\" alt=\"hero\"></body></html>"

        let result: String = await preloader.preloadImages(in: html)

        XCTAssertFalse(result.contains(url))
        XCTAssertTrue(result.contains("data:image/png;base64,"))
    }

    func testSingleQuotedImageSourcesAreInlined() async throws {
        let url = "https://cdn.qonversion.io/hero.png"
        register(url: url, bytes: pngBytes, contentType: "image/png")
        let preloader: ImagePreloader = makePreloader()
        let html = "<img src='\(url)'>"

        let result: String = await preloader.preloadImages(in: html)

        XCTAssertFalse(result.contains(url))
    }

    func testBackgroundImageUrlsAreInlined() async throws {
        let url = "https://cdn.qonversion.io/bg.jpg"
        register(url: url, bytes: jpegBytes, contentType: "image/jpeg")
        let preloader: ImagePreloader = makePreloader()
        let html = "<div style=\"background-image: url('\(url)')\"></div>"

        let result: String = await preloader.preloadImages(in: html)

        XCTAssertFalse(result.contains(url))
        XCTAssertTrue(result.contains("data:image/jpeg;base64,"))
    }

    func testUnquotedBackgroundImageUrlsAreInlined() async throws {
        let url = "https://cdn.qonversion.io/bg.jpg"
        register(url: url, bytes: jpegBytes, contentType: "image/jpeg")
        let preloader: ImagePreloader = makePreloader()
        let html = "<div style=\"background-image:url(\(url))\"></div>"

        let result: String = await preloader.preloadImages(in: html)

        XCTAssertFalse(result.contains(url))
    }

    func testEveryImageInTheDocumentIsInlined() async throws {
        let first = "https://cdn.qonversion.io/one.png"
        let second = "https://cdn.qonversion.io/two.png"
        register(url: first, bytes: pngBytes, contentType: "image/png")
        register(url: second, bytes: pngBytes, contentType: "image/png")
        let preloader: ImagePreloader = makePreloader()
        let html = "<img src=\"\(first)\"><div style=\"background-image: url(\(second))\"></div>"

        let result: String = await preloader.preloadImages(in: html)

        XCTAssertFalse(result.contains(first))
        XCTAssertFalse(result.contains(second))
    }

    // MARK: - Filtering

    func testOnlyHttpAndHttpsSourcesAreDownloaded() async throws {
        let preloader: ImagePreloader = makePreloader()
        let html = """
        <img src="data:image/png;base64,AAAA">
        <img src="/local/asset.png">
        <img src="ftp://files.example.com/asset.png">
        """

        let result: String = await preloader.preloadImages(in: html)

        XCTAssertEqual(result, html)
        XCTAssertEqual(StubURLProtocol.registry.requestedUrlsCount, 0)
    }

    func testMarkupWithoutImagesIsReturnedUnchanged() async throws {
        let preloader: ImagePreloader = makePreloader()
        let html = "<html><body><p>no pictures here</p></body></html>"

        let result: String = await preloader.preloadImages(in: html)

        XCTAssertEqual(result, html)
        XCTAssertEqual(StubURLProtocol.registry.requestedUrlsCount, 0)
    }

    // MARK: - Payload

    func testTheInlinedPayloadIsTheDownloadedBytes() async throws {
        let url = "https://cdn.qonversion.io/hero.png"
        let bytes: Data = pngBytes
        register(url: url, bytes: bytes, contentType: "image/png")
        let preloader: ImagePreloader = makePreloader()
        let html = "<img src=\"\(url)\">"

        let result: String = await preloader.preloadImages(in: html)

        let prefix = "data:image/png;base64,"
        let start: Range<String.Index> = try XCTUnwrap(result.range(of: prefix))
        let end: Range<String.Index> = try XCTUnwrap(result.range(of: "\">", range: start.upperBound..<result.endIndex))
        let base64 = String(result[start.upperBound..<end.lowerBound])
        let decoded: Data = try XCTUnwrap(Data(base64Encoded: base64))
        XCTAssertEqual(decoded, bytes)
    }

    // MARK: - Failures

    func testAFailedDownloadLeavesTheOriginalUrlInPlace() async throws {
        let url = "https://cdn.qonversion.io/missing.png"
        register(url: url, bytes: pngBytes, contentType: "image/png", statusCode: 404)
        let preloader: ImagePreloader = makePreloader()
        let html = "<img src=\"\(url)\">"

        let result: String = await preloader.preloadImages(in: html)

        XCTAssertEqual(result, html)
    }

    func testAnUnreachableUrlLeavesTheOriginalUrlInPlace() async throws {
        let preloader: ImagePreloader = makePreloader()
        let html = "<img src=\"https://cdn.qonversion.io/never-registered.png\">"

        let result: String = await preloader.preloadImages(in: html)

        XCTAssertEqual(result, html)
    }

    func testTheDownloadDeadlineAbandonsAStalledImage() async throws {
        let url = "https://cdn.qonversion.io/stalled.png"
        let resource = StubbedResource(data: Data(), statusCode: 200, contentType: "image/png", hangs: true)
        StubURLProtocol.registry.register(url: url, resource: resource)
        let preloader: ImagePreloader = makePreloader(timeout: 0.2)
        let html = "<img src=\"\(url)\">"

        let start: Date = Date()
        let result: String = await preloader.preloadImages(in: html)
        let elapsed: TimeInterval = Date().timeIntervalSince(start)

        XCTAssertEqual(result, html, "the stalled image keeps its original URL")
        XCTAssertLessThan(elapsed, 3.0, "the deadline, not the URLSession timeout, ended the wait")
    }

    // MARK: - MIME resolution

    func testTheResponseMimeTypeWins() {
        let preloader: ImagePreloader = makePreloader()
        let url = URL(string: "https://cdn.qonversion.io/asset.png")!
        let response = SilentMimeTypeResponse(url: url, mimeType: "image/gif")

        let mimeType: String = preloader.detectMimeType(from: response, data: pngBytes, url: url)

        XCTAssertEqual(mimeType, "image/gif")
    }

    func testKnownExtensionsMapToTheirMimeTypesWhenTheResponseIsSilent() {
        let preloader: ImagePreloader = makePreloader()
        let expectations: [String: String] = [
            "asset.png": "image/png",
            "asset.jpg": "image/jpeg",
            "asset.jpeg": "image/jpeg",
            "asset.gif": "image/gif",
            "asset.webp": "image/webp",
            "asset.svg": "image/svg+xml",
            "asset.ico": "image/x-icon",
            "asset.bmp": "image/bmp"
        ]

        for (fileName, expected) in expectations {
            let url = URL(string: "https://cdn.qonversion.io/" + fileName)!
            let response = SilentMimeTypeResponse(url: url, mimeType: nil)

            let mimeType: String = preloader.detectMimeType(from: response, data: Data(), url: url)

            XCTAssertEqual(mimeType, expected, fileName)
        }
    }

    func testUppercaseExtensionsAreResolved() {
        let preloader: ImagePreloader = makePreloader()
        let url = URL(string: "https://cdn.qonversion.io/ASSET.PNG")!
        let response = SilentMimeTypeResponse(url: url, mimeType: nil)

        let mimeType: String = preloader.detectMimeType(from: response, data: Data(), url: url)

        XCTAssertEqual(mimeType, "image/png")
    }

    func testMagicBytesResolveTheMimeTypeForAnUnknownExtension() {
        let preloader: ImagePreloader = makePreloader()
        let url = URL(string: "https://cdn.qonversion.io/asset.bin")!
        let response = SilentMimeTypeResponse(url: url, mimeType: nil)

        XCTAssertEqual(preloader.detectMimeType(from: response, data: pngBytes, url: url), "image/png")
        XCTAssertEqual(preloader.detectMimeType(from: response, data: jpegBytes, url: url), "image/jpeg")
        XCTAssertEqual(preloader.detectMimeType(from: response, data: gifBytes, url: url), "image/gif")
        XCTAssertEqual(preloader.detectMimeType(from: response, data: webpBytes, url: url), "image/webp")
    }

    func testUnrecognizedPayloadsFallBackToPng() {
        let preloader: ImagePreloader = makePreloader()
        let url = URL(string: "https://cdn.qonversion.io/asset.bin")!
        let response = SilentMimeTypeResponse(url: url, mimeType: nil)
        let bytes: Data = Data([0x01, 0x02, 0x03, 0x04, 0x05])

        XCTAssertEqual(preloader.detectMimeType(from: response, data: bytes, url: url), "image/png")
        XCTAssertNil(preloader.detectMimeTypeFromData(bytes))
    }

    func testTooShortPayloadsCannotBeSniffed() {
        let preloader: ImagePreloader = makePreloader()
        let bytes: Data = Data([0x89, 0x50])

        XCTAssertNil(preloader.detectMimeTypeFromData(bytes))
    }

    func testAnEmptyResponseMimeTypeIsIgnored() {
        let preloader: ImagePreloader = makePreloader()
        let url = URL(string: "https://cdn.qonversion.io/asset.jpg")!
        let response = SilentMimeTypeResponse(url: url, mimeType: "")

        let mimeType: String = preloader.detectMimeType(from: response, data: Data(), url: url)

        XCTAssertEqual(mimeType, "image/jpeg")
    }

    // MARK: - Private

    private var pngBytes: Data {
        return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01, 0x02, 0x03])
    }

    private var jpegBytes: Data {
        return Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01])
    }

    private var gifBytes: Data {
        return Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00])
    }

    private var webpBytes: Data {
        return Data([0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50])
    }

    private func makePreloader(timeout: TimeInterval = 5.0) -> ImagePreloader {
        let configuration: URLSessionConfiguration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)

        return ImagePreloader(urlSession: session, timeout: timeout, maxConcurrentDownloads: 5)
    }

    private func register(url: String, bytes: Data, contentType: String?, statusCode: Int = 200) {
        let resource = StubbedResource(data: bytes, statusCode: statusCode, contentType: contentType, hangs: false)
        StubURLProtocol.registry.register(url: url, resource: resource)
    }
}
