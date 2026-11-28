import XCTest
@testable import PixyDbg

// MARK: - 版本号解析与比较

final class SemanticVersionTests: XCTestCase {
    private func v(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> SemanticVersion {
        guard let version = SemanticVersion(text) else {
            XCTFail("应当能解析：\(text)", file: file, line: line)
            return SemanticVersion("0.0.0")!
        }
        return version
    }

    // MARK: 解析

    func testParsesPlainAndPrefixedVersions() {
        for text in ["0.0.6", "v0.0.6"] {
            let version = v(text)
            XCTAssertEqual([version.major, version.minor, version.patch], [0, 0, 6], text)
            XCTAssertNil(version.prerelease, text)
        }
        let big = v("v10.20.30")
        XCTAssertEqual([big.major, big.minor, big.patch], [10, 20, 30])
    }

    func testMissingSegmentsAreFilledWithZero() {
        XCTAssertEqual(v("1.2"), v("1.2.0"))
        XCTAssertEqual(v("3"), v("3.0.0"))
        XCTAssertEqual(v("v3"), v("3.0.0"))
        XCTAssertEqual(v("1.2").description, "1.2.0")
    }

    func testParsesPrereleaseSuffix() {
        XCTAssertEqual(v("0.0.7-rc1").prerelease, "rc1")
        XCTAssertEqual(v("v1.0.0-rc.1").prerelease, "rc.1")
        XCTAssertEqual(v("1.0.0-alpha-1").prerelease, "alpha-1", "后缀内部的连字符属于预发布标识")
        XCTAssertEqual(v("1.2-beta").prerelease, "beta")
        XCTAssertEqual(v("0.0.7-rc1").description, "0.0.7-rc1")
    }

    func testBuildMetadataIsDiscarded() {
        XCTAssertNil(v("0.0.6+2026112601").prerelease)
        XCTAssertEqual(v("0.0.6+2026112601").description, "0.0.6")
        XCTAssertEqual(v("0.0.7-rc1+build.5").prerelease, "rc1")
        XCTAssertEqual(v("0.0.7-rc1+build.5").description, "0.0.7-rc1")
    }

    func testRejectsInvalidInput() {
        let invalid = [
            "", "v", "V1.0.0", "vv1.0.0", "abc", "latest", "v-1",
            "1.2.3.4", "1.2.3.4.5",                 // 4 段及以上
            "1..3", ".1", "1.", "1.2.", "..",       // 空段
            "-1.0.0", "1.-1.0", "1.0.-1", "+1.0.0", // 负号 / 加号
            "1.0.0-", "1.0.0+", "1.0.0-+x",         // 空后缀
            "1.0.0-rc..1", "1.0.0-.rc", "1.0.0-rc.", // 预发布里的空标识
            "1.0.0-01", "1.0.0-rc.01",              // 预发布里带前导零的数字标识
            "1.0.0-rc 1", "1.0.0-é", "1.0.0-rc_1",  // 预发布里的非法字符
            "1.0.0+a+b", "1.0.0+a b",               // 元数据里的非法字符
            " 1.0.0", "1.0.0 ", "1.0.0\n", "\t1.0.0", "1 .0.0", // 空白一律不容忍
            "1.0.0abc", "abc1.0.0", "1.0a.0", "1,0,0", "1_0_0",   // 前导 / 尾随垃圾
            "1.0.0/evil", "../1.0.0", "1.0.0;rm",
            "٣.٠.٠", "１.０.０",                      // 非 ASCII 数字
            "99999999999999999999.0.0",             // 溢出
            "0x1.0.0", "1e3.0.0", "+1.2.3",
        ]
        for text in invalid {
            XCTAssertNil(SemanticVersion(text), "应当拒绝：\(text.debugDescription)")
        }
    }

    // MARK: 比较

    func testComparesNumericallyNotLexically() {
        XCTAssertGreaterThan(v("0.0.10"), v("0.0.9"))
        XCTAssertGreaterThan(v("0.1.0"), v("0.0.99"))
        XCTAssertGreaterThan(v("1.0.0"), v("0.99.99"))
        XCTAssertGreaterThan(v("0.10.0"), v("0.9.0"))
        XCTAssertGreaterThan(v("10.0.0"), v("9.9.9"))
        XCTAssertLessThan(v("0.0.6"), v("0.0.7"))
    }

    func testDifferentSegmentCountsCompareAsIfPaddedWithZero() {
        XCTAssertEqual(v("1.2"), v("1.2.0"))
        XCTAssertGreaterThan(v("1.2.1"), v("1.2"))
        XCTAssertLessThan(v("1.2"), v("1.10"))
        XCTAssertGreaterThan(v("2"), v("1.99.99"))
    }

    func testVPrefixDoesNotAffectComparison() {
        XCTAssertEqual(v("v0.0.6"), v("0.0.6"))
        XCTAssertGreaterThan(v("v0.0.7"), v("0.0.6"))
    }

    func testPrereleaseIsLowerThanTheSameRelease() {
        XCTAssertLessThan(v("0.0.7-rc1"), v("0.0.7"))
        XCTAssertGreaterThan(v("0.0.7"), v("0.0.7-rc1"))
        XCTAssertGreaterThan(v("0.0.7-rc1"), v("0.0.6"), "预发布仍然高于更早的正式版")
        XCTAssertLessThan(v("0.0.7-rc1"), v("0.0.8"))
        XCTAssertNotEqual(v("0.0.7-rc1"), v("0.0.7"))
    }

    func testPrereleaseOrderingFollowsSemverPrecedence() {
        // semver.org 给出的示例序列
        let ordered = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta",
                       "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"]
        for (lower, higher) in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThan(v(lower), v(higher), "\(lower) < \(higher)")
            XCTAssertGreaterThan(v(higher), v(lower), "\(higher) > \(lower)")
        }
        XCTAssertLessThan(v("0.0.7-rc1"), v("0.0.7-rc2"))
        XCTAssertLessThan(v("0.0.7-rc.2"), v("0.0.7-rc.10"), "数字标识按数值比较")
        XCTAssertEqual(v("0.0.7-rc1"), v("0.0.7-rc1"))
    }

    func testBuildMetadataDoesNotParticipateInComparison() {
        XCTAssertEqual(v("0.0.6+1"), v("0.0.6+999999"))
        XCTAssertFalse(v("0.0.6+1") < v("0.0.6+999999"))
        XCTAssertFalse(v("0.0.6+999999") < v("0.0.6+1"))
        XCTAssertEqual(v("0.0.6+2026112601"), v("0.0.6"))
        // 应用 build 号（YYYYMMDDNN）更大也不会让同一个版本号显得更新
        XCTAssertFalse(v("0.0.6+2026112602") > v("0.0.6+2026112601"))
        XCTAssertGreaterThan(v("0.0.7+1"), v("0.0.6+2026112699"))
    }

    func testSortingAFewVersions() {
        let shuffled = ["v0.0.10", "0.0.2", "0.0.9", "0.0.10-rc1", "0.1.0", "0.0.1"].map { v($0) }
        XCTAssertEqual(shuffled.sorted().map(\.description),
                       ["0.0.1", "0.0.2", "0.0.9", "0.0.10-rc1", "0.0.10", "0.1.0"])
    }
}

// MARK: - 响应解析与链接校验

final class UpdateCheckerParsingTests: XCTestCase {
    private let page = "https://github.com/natinli/Pixy/releases/tag/v0.0.7"

    private func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private func parse(_ object: Any, allowLoopback: Bool = false) -> Result<LatestRelease, UpdateCheckFailure> {
        UpdateChecker.parseLatestRelease(json(object), allowLoopback: allowLoopback)
    }

    private func assertFailure(_ result: Result<LatestRelease, UpdateCheckFailure>, _ expected: UpdateCheckFailure,
                               file: StaticString = #filePath, line: UInt = #line) {
        switch result {
        case .success(let release): XCTFail("应当失败，却解析出 \(release)", file: file, line: line)
        case .failure(let failure): XCTAssertEqual(failure, expected, file: file, line: line)
        }
    }

    func testParsesTagAndPageURL() throws {
        let release = try parse(["tag_name": "v0.0.7", "html_url": page]).get()
        XCTAssertEqual(release.version, SemanticVersion("0.0.7"))
        XCTAssertEqual(release.pageURL, URL(string: page))
    }

    func testIgnoresUnrelatedFieldsInARealisticResponse() throws {
        let body: [String: Any] = [
            "url": "https://api.github.com/repos/natinli/Pixy/releases/1",
            "id": 1, "tag_name": "v0.0.7", "name": "Pixy 0.0.7（未签名）",
            "draft": false, "prerelease": false,
            "html_url": page,
            "assets": [["name": "Pixy-0.0.7-universal-unsigned.dmg", "size": 123, "download_count": 4]],
            "body": "release notes",
        ]
        let release = try parse(body).get()
        XCTAssertEqual(release.version.description, "0.0.7")
    }

    func testMissingOrMistypedFieldsFail() {
        assertFailure(parse(["html_url": page]), .invalidResponse)
        assertFailure(parse(["tag_name": "v0.0.7"]), .invalidResponse)
        assertFailure(parse(["tag_name": 7, "html_url": page]), .invalidResponse)
        assertFailure(parse(["tag_name": "v0.0.7", "html_url": 7]), .invalidResponse)
        assertFailure(parse(["tag_name": NSNull(), "html_url": page]), .invalidResponse)
        assertFailure(parse(["tag_name": ["v0.0.7"], "html_url": page]), .invalidResponse)
        assertFailure(parse(["tag_name": "", "html_url": page]), .invalidResponse)
        assertFailure(parse(["tag_name": "v0.0.7", "html_url": ""]), .invalidResponse)
        assertFailure(parse(["tag_name": "latest", "html_url": page]), .invalidResponse)
        assertFailure(parse(["tag_name": "v1.2.3.4", "html_url": page]), .invalidResponse)
    }

    func testNonObjectOrBrokenPayloadsFail() {
        assertFailure(UpdateChecker.parseLatestRelease(Data()), .invalidResponse)
        assertFailure(UpdateChecker.parseLatestRelease(Data("<html>Rate limited</html>".utf8)), .invalidResponse)
        assertFailure(UpdateChecker.parseLatestRelease(Data("{\"tag_name\":".utf8)), .invalidResponse)
        assertFailure(UpdateChecker.parseLatestRelease(Data("null".utf8)), .invalidResponse)
        assertFailure(parse([String]()), .invalidResponse)
        assertFailure(parse(["tag_name", "html_url"]), .invalidResponse)
        assertFailure(UpdateChecker.parseLatestRelease(Data("\"v0.0.7\"".utf8)), .invalidResponse)
    }

    func testDraftAndPrereleaseAreRejected() {
        assertFailure(parse(["tag_name": "v0.0.7", "html_url": page, "draft": true]), .invalidResponse)
        assertFailure(parse(["tag_name": "v0.0.7", "html_url": page, "prerelease": true]), .invalidResponse)
        assertFailure(parse(["tag_name": "v0.0.7", "html_url": page, "draft": true, "prerelease": true]), .invalidResponse)
        XCTAssertNoThrow(try parse(["tag_name": "v0.0.7", "html_url": page, "draft": false, "prerelease": false]).get())
    }

    func testOversizedResponseIsRejected() throws {
        let padding = String(repeating: "A", count: UpdateChecker.maxResponseBytes)
        let body = json(["tag_name": "v0.0.7", "html_url": page, "body": padding])
        XCTAssertGreaterThan(body.count, UpdateChecker.maxResponseBytes)
        assertFailure(UpdateChecker.parseLatestRelease(body), .invalidResponse)

        // 刚好在上限内的正常响应不受影响
        let small = json(["tag_name": "v0.0.7", "html_url": page, "body": String(repeating: "A", count: 4096)])
        XCTAssertNoThrow(try UpdateChecker.parseLatestRelease(small).get())
    }

    func testReleasePageMustBeHTTPSGitHub() {
        let untrusted = [
            "http://github.com/natinli/Pixy/releases/tag/v0.0.7",
            "https://evil.example/natinli/Pixy",
            "https://github.com.evil.example/natinli/Pixy",
            "https://evil.example/github.com/natinli/Pixy",
            "https://www.github.com/natinli/Pixy",
            "https://user@github.com/natinli/Pixy",
            "https://user:pw@github.com/natinli/Pixy",
            "https://github.com:8443/natinli/Pixy",
            "ftp://github.com/natinli/Pixy",
            "file:///etc/passwd",
            "javascript:alert(1)",
            "github.com/natinli/Pixy",
            "//github.com/natinli/Pixy",
            "https://127.0.0.1:8000/x",
            "http://127.0.0.1:8000/x",
            "http://localhost:8000/x",
        ]
        for url in untrusted {
            assertFailure(parse(["tag_name": "v0.0.7", "html_url": url]), .untrustedReleaseURL)
        }
    }

    func testTrustedReleasePagesAreAccepted() throws {
        for url in ["https://github.com/natinli/Pixy/releases/tag/v0.0.7",
                    "https://GitHub.com/natinli/Pixy/releases/tag/v0.0.7",
                    "HTTPS://github.com/natinli/Pixy"] {
            let release = try parse(["tag_name": "v0.0.7", "html_url": url]).get()
            XCTAssertEqual(release.pageURL.absoluteString, url)
        }
    }

    func testLoopbackPagesAreOnlyAcceptedWhenExplicitlyAllowed() throws {
        let local = ["http://127.0.0.1:8000/release", "https://127.0.0.1:8000/release", "http://localhost:8000/release"]
        for url in local {
            assertFailure(parse(["tag_name": "v0.0.7", "html_url": url]), .untrustedReleaseURL)
            XCTAssertNoThrow(try parse(["tag_name": "v0.0.7", "html_url": url], allowLoopback: true).get(), url)
        }
        // 放宽只针对回环地址，其它主机仍然拒绝
        assertFailure(parse(["tag_name": "v0.0.7", "html_url": "https://evil.example/x"], allowLoopback: true), .untrustedReleaseURL)
        assertFailure(parse(["tag_name": "v0.0.7", "html_url": "http://github.com/x"], allowLoopback: true), .untrustedReleaseURL)
        assertFailure(parse(["tag_name": "v0.0.7", "html_url": "http://127.0.0.1.evil.example/x"], allowLoopback: true), .untrustedReleaseURL)
    }
}

// MARK: - 请求构造与会话配置

final class UpdateCheckerRequestTests: XCTestCase {
    func testDefaultEndpointIsLatestReleaseOfThisRepository() {
        XCTAssertEqual(UpdateChecker.defaultEndpoint.absoluteString,
                       "https://api.github.com/repos/natinli/Pixy/releases/latest")
    }

    func testRequestIsASingleBareGET() throws {
        let request = UpdateChecker.makeRequest(endpoint: UpdateChecker.defaultEndpoint,
                                                appVersion: SemanticVersion("0.0.6")!)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url, UpdateChecker.defaultEndpoint)
        XCTAssertEqual(request.timeoutInterval, 10)
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.httpBodyStream)
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNil(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.query, "不带 query")
    }

    func testRequestCarriesExactlyTheseHeaders() {
        let request = UpdateChecker.makeRequest(endpoint: UpdateChecker.defaultEndpoint,
                                                appVersion: SemanticVersion("0.0.6")!)
        // Accept-Language 固定为 "en"：不设的话系统会自动附带用户的界面语言偏好，那是能识别用户的信息
        XCTAssertEqual(request.allHTTPHeaderFields,
                       ["Accept": "application/vnd.github+json", "User-Agent": "Pixy/0.0.6", "Accept-Language": "en"])
        for forbidden in ["Authorization", "Cookie", "X-GitHub-Api-Version", "Referer"] {
            XCTAssertNil(request.value(forHTTPHeaderField: forbidden), forbidden)
        }
    }

    func testUserAgentCarriesTheMarketingVersionOnly() {
        // build 号 / 元数据 / 预发布后缀里的杂项都不应出现在请求里的标识上（预发布后缀本身属于版本号）
        let withBuild = UpdateChecker.makeRequest(endpoint: UpdateChecker.defaultEndpoint,
                                                  appVersion: SemanticVersion("0.0.6+2026112601")!)
        XCTAssertEqual(withBuild.value(forHTTPHeaderField: "User-Agent"), "Pixy/0.0.6")
    }

    func testSessionConfigurationStoresNothing() {
        let config = UpdateChecker.makeSessionConfiguration()
        XCTAssertNil(config.httpCookieStorage)
        XCTAssertNil(config.urlCredentialStorage)
        XCTAssertNil(config.urlCache)
        XCTAssertFalse(config.httpShouldSetCookies)
        XCTAssertEqual(config.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(config.timeoutIntervalForRequest, 10)
        XCTAssertLessThanOrEqual(config.timeoutIntervalForResource, 30, "总时长也要有上限，防止慢速拖住")
        XCTAssertFalse(config.waitsForConnectivity, "离线时立即失败，不排队等网")
        XCTAssertNil(config.httpAdditionalHeaders)
        XCTAssertNil(config.identifier, "ephemeral 配置没有后台会话标识")
    }

    func testUpgradeCommandIsLiteral() {
        XCTAssertEqual(UpdateChecker.upgradeCommand, "brew upgrade --cask pixy")
    }

    func testEndpointIsNotOverriddenWithoutTheDebugVariable() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["PIXY_UPDATE_URL"] != nil, "本次运行设置了覆盖变量")
        XCTAssertEqual(UpdateChecker.endpoint, UpdateChecker.defaultEndpoint)
        XCTAssertFalse(UpdateChecker.allowsLoopbackReleaseURL)
    }
}

// MARK: - 用 URLProtocol 桩验证整条检查路径

private final class UpdateStubURLProtocol: URLProtocol {
    enum Outcome {
        case response(status: Int, body: Data)
        case failure(Error)
    }

    private static let lock = NSLock()
    private static var _outcome: Outcome = .failure(URLError(.badURL))
    private static var _requests: [URLRequest] = []

    static var outcome: Outcome {
        get { lock.lock(); defer { lock.unlock() }; return _outcome }
        set { lock.lock(); defer { lock.unlock() }; _outcome = newValue }
    }
    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }; return _requests
    }
    static func reset(_ outcome: Outcome) {
        lock.lock(); defer { lock.unlock() }
        _outcome = outcome
        _requests = []
    }
    private static func record(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        _requests.append(request)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.record(request)
        switch Self.outcome {
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .response(let status, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

final class UpdateCheckerNetworkTests: XCTestCase {
    private let page = "https://github.com/natinli/Pixy/releases/tag/v0.0.7"

    private func releaseBody(tag: String, url: String? = nil) -> Data {
        try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": url ?? page, "draft": false, "prerelease": false])
    }

    private func stubbedSession() -> URLSession {
        let config = UpdateChecker.makeSessionConfiguration()
        config.protocolClasses = [UpdateStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// 跑一次检查：返回结果，并在回调之后再等一会儿，确认没有重试或多余请求。
    @discardableResult
    private func runCheck(current: String?, outcome: UpdateStubURLProtocol.Outcome,
                          allowLoopback: Bool = false,
                          file: StaticString = #filePath, line: UInt = #line) -> UpdateCheckResult {
        UpdateStubURLProtocol.reset(outcome)
        let done = expectation(description: "check finished")
        var captured: UpdateCheckResult?
        UpdateChecker.check(currentVersion: current,
                            endpoint: UpdateChecker.defaultEndpoint,
                            allowLoopbackReleaseURL: allowLoopback,
                            session: stubbedSession()) { result in
            captured = result
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
        return captured ?? .failed(.network)
    }

    private var sentRequests: [URLRequest] { UpdateStubURLProtocol.requests }

    private func assertSingleRequest(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(sentRequests.count, 1, "一次检查恰好发出 1 个请求", file: file, line: line)
        guard let request = sentRequests.first else { return }
        XCTAssertEqual(request.httpMethod, "GET", file: file, line: line)
        XCTAssertEqual(request.url, UpdateChecker.defaultEndpoint, file: file, line: line)
        XCTAssertEqual(request.timeoutInterval, 10, file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json", file: file, line: line)
        XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Pixy/") == true, file: file, line: line)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), file: file, line: line)
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"), file: file, line: line)
        XCTAssertNil(request.httpBody, file: file, line: line)
    }

    func testNewerReleaseIsReported() {
        let result = runCheck(current: "0.0.6", outcome: .response(status: 200, body: releaseBody(tag: "v0.0.7")))
        XCTAssertEqual(result, .updateAvailable(current: SemanticVersion("0.0.6")!,
                                                latest: SemanticVersion("0.0.7")!,
                                                releaseURL: URL(string: page)!))
        assertSingleRequest()
        XCTAssertEqual(sentRequests.first?.value(forHTTPHeaderField: "User-Agent"), "Pixy/0.0.6")
    }

    func testSameVersionIsUpToDate() {
        let result = runCheck(current: "0.0.6", outcome: .response(status: 200, body: releaseBody(tag: "v0.0.6")))
        XCTAssertEqual(result, .upToDate(current: SemanticVersion("0.0.6")!))
        assertSingleRequest()
    }

    func testOlderLatestIsStillUpToDate() {
        let result = runCheck(current: "0.0.6", outcome: .response(status: 200, body: releaseBody(tag: "v0.0.5")))
        XCTAssertEqual(result, .upToDate(current: SemanticVersion("0.0.6")!))
        assertSingleRequest()
    }

    func testRunningANewerBuildThanLatestIsUpToDate() {
        let result = runCheck(current: "0.0.8", outcome: .response(status: 200, body: releaseBody(tag: "v0.0.7")))
        XCTAssertEqual(result, .upToDate(current: SemanticVersion("0.0.8")!))
        assertSingleRequest()
    }

    func testAppBuildNumberInTheCurrentVersionIsIgnored() {
        let result = runCheck(current: "0.0.6+2026112601", outcome: .response(status: 200, body: releaseBody(tag: "v0.0.6")))
        XCTAssertEqual(result, .upToDate(current: SemanticVersion("0.0.6")!))
        XCTAssertEqual(sentRequests.first?.value(forHTTPHeaderField: "User-Agent"), "Pixy/0.0.6")
    }

    func testPrereleaseBuildIsOfferedTheFinalRelease() {
        let result = runCheck(current: "0.0.7-rc1", outcome: .response(status: 200, body: releaseBody(tag: "v0.0.7")))
        guard case .updateAvailable(let current, let latest, _) = result else { return XCTFail("应提示新版：\(result)") }
        XCTAssertEqual(current.description, "0.0.7-rc1")
        XCTAssertEqual(latest.description, "0.0.7")
    }

    func testHTTPErrorsFail() {
        for status in [404, 403, 429, 500, 502, 301, 204] {
            let result = runCheck(current: "0.0.6", outcome: .response(status: status, body: releaseBody(tag: "v9.9.9")))
            XCTAssertEqual(result, .failed(.httpStatus(status)), "status \(status)")
            assertSingleRequest()
        }
    }

    func testGarbageBodiesFail() {
        let bodies: [Data] = [Data("not json".utf8), Data("<html></html>".utf8), Data("{}".utf8), Data("[]".utf8),
                              Data("{\"tag_name\":\"v0.0.7\"}".utf8)]
        for body in bodies {
            let result = runCheck(current: "0.0.6", outcome: .response(status: 200, body: body))
            XCTAssertEqual(result, .failed(.invalidResponse), String(data: body, encoding: .utf8) ?? "")
            assertSingleRequest()
        }
    }

    func testEmptyResponseFails() {
        let result = runCheck(current: "0.0.6", outcome: .response(status: 200, body: Data()))
        XCTAssertEqual(result, .failed(.invalidResponse))
        assertSingleRequest()
    }

    func testUntrustedReleasePageFailsInsteadOfOfferingAnArbitraryLink() {
        let result = runCheck(current: "0.0.6",
                              outcome: .response(status: 200, body: releaseBody(tag: "v0.0.7", url: "https://evil.example/pixy")))
        XCTAssertEqual(result, .failed(.untrustedReleaseURL))
        assertSingleRequest()
    }

    func testLoopbackReleasePageIsOnlyTrustedWhenAllowed() {
        let body = releaseBody(tag: "v0.0.7", url: "http://127.0.0.1:8000/release")
        XCTAssertEqual(runCheck(current: "0.0.6", outcome: .response(status: 200, body: body)), .failed(.untrustedReleaseURL))
        let allowed = runCheck(current: "0.0.6", outcome: .response(status: 200, body: body), allowLoopback: true)
        XCTAssertEqual(allowed, .updateAvailable(current: SemanticVersion("0.0.6")!, latest: SemanticVersion("0.0.7")!,
                                                 releaseURL: URL(string: "http://127.0.0.1:8000/release")!))
    }

    func testNetworkErrorsFailWithoutRetry() {
        let errors: [URLError.Code] = [.notConnectedToInternet, .timedOut, .cannotFindHost, .cannotConnectToHost,
                                       .networkConnectionLost, .secureConnectionFailed, .dnsLookupFailed]
        for code in errors {
            let result = runCheck(current: "0.0.6", outcome: .failure(URLError(code)))
            XCTAssertEqual(result, .failed(.network), "\(code)")
            assertSingleRequest()
        }
    }

    func testUnparseableCurrentVersionFailsWithoutAnyRequest() {
        for current in [nil, "", "garbage", "1.2.3.4", " 0.0.6"] as [String?] {
            let result = runCheck(current: current, outcome: .response(status: 200, body: releaseBody(tag: "v0.0.7")))
            XCTAssertEqual(result, .failed(.invalidCurrentVersion), "\(String(describing: current))")
            XCTAssertEqual(sentRequests.count, 0, "当前版本读不出来时不应联网")
        }
    }
}
