//
//  UpdateChecker.swift
//  FlowVision
//
//  「检查更新…」的版本比较、请求与响应解析。
//  Version comparison, request and response parsing for "Check for Updates…".
//
//  这是整个应用里**唯一**的联网代码（全工程只有本文件出现 URLSession / URLRequest），
//  并且只会被菜单「检查更新…」触发：没有启动检查、定时检查或后台检查，也没有自动更新。
//  This is the only networking code in the app (URLSession / URLRequest appear nowhere else),
//  and it runs only when the user picks "Check for Updates…": no launch-time, scheduled or
//  background checks, and no auto-update.
//

import Foundation

// MARK: - 版本号

/// 主.次.修订 + 可选预发布后缀，用于比较「当前版本」与「最新发布」。
/// 解析：`v0.0.6`、`0.0.6`、`1.2`（缺的补 0）、`0.0.7-rc1`、`0.0.6+2026112601`；
/// `+元数据`（如应用的 build 号 YYYYMMDDNN）解析后丢弃，不参与比较；
/// 4 段及以上、空串、非数字、负号、空白、前导 / 尾随垃圾一律返回 nil。
/// 预发布后缀按 semver 的优先级规则比较，且始终低于同号正式版（`0.0.7-rc1` < `0.0.7`，但 > `0.0.6`）。
struct SemanticVersion: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    /// 预发布后缀（`-` 之后、`+` 之前的部分），正式版为 nil
    let prerelease: String?

    init?(_ text: String) {
        var bytes = Array(text.utf8)[...]
        if bytes.first == UInt8(ascii: "v") { bytes = bytes.dropFirst() }

        // 构建元数据：只做字符校验，然后丢弃
        if let plus = bytes.firstIndex(of: UInt8(ascii: "+")) {
            guard SemanticVersion.isValidIdentifierList(bytes[(plus + 1)...], rejectLeadingZeros: false) else { return nil }
            bytes = bytes[..<plus]
        }

        var prerelease: String?
        if let dash = bytes.firstIndex(of: UInt8(ascii: "-")) {
            let suffix = bytes[(dash + 1)...]
            guard SemanticVersion.isValidIdentifierList(suffix, rejectLeadingZeros: true) else { return nil }
            prerelease = String(decoding: suffix, as: UTF8.self)
            bytes = bytes[..<dash]
        }

        let parts = bytes.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ SemanticVersion.isDigit($0) }),
                  let number = Int(String(decoding: part, as: UTF8.self)) else { return nil }
            numbers.append(number)
        }
        major = numbers[0]
        minor = numbers.count > 1 ? numbers[1] : 0
        patch = numbers.count > 2 ? numbers[2] : 0
        self.prerelease = prerelease
    }

    var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.map { core + "-" + $0 } ?? core
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.prerelease, rhs.prerelease) {
        case (_, nil): return lhs.prerelease != nil   // 预发布 < 同号正式版；正式版之间相等
        case (nil, _?): return false
        case let (l?, r?): return comparePrerelease(l, r) < 0
        }
    }

    // MARK: 内部

    private static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }

    private static func isIdentifierByte(_ byte: UInt8) -> Bool {
        isDigit(byte) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == UInt8(ascii: "-")
    }

    /// 点分隔的标识列表：每项非空、只含 [0-9A-Za-z-]；预发布里纯数字的标识不允许前导零（semver 规定）。
    private static func isValidIdentifierList(_ bytes: ArraySlice<UInt8>, rejectLeadingZeros: Bool) -> Bool {
        let identifiers = bytes.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: false)
        guard !identifiers.isEmpty else { return false }
        for identifier in identifiers {
            guard !identifier.isEmpty, identifier.allSatisfy({ isIdentifierByte($0) }) else { return false }
            if rejectLeadingZeros, identifier.count > 1, identifier.first == UInt8(ascii: "0"),
               identifier.allSatisfy({ isDigit($0) }) { return false }
        }
        return true
    }

    /// semver 预发布优先级：纯数字标识按数值比较且低于字母标识；其余按 ASCII 比较；前缀相同时标识更少的更低。
    private static func comparePrerelease(_ lhs: String, _ rhs: String) -> Int {
        let l = lhs.split(separator: ".", omittingEmptySubsequences: false)
        let r = rhs.split(separator: ".", omittingEmptySubsequences: false)
        for (a, b) in zip(l, r) {
            let aNumeric = a.utf8.allSatisfy { isDigit($0) }
            let bNumeric = b.utf8.allSatisfy { isDigit($0) }
            if aNumeric && bNumeric {
                // 无前导零，位数多的更大，位数相同按字典序；不转成整数，避免溢出
                if a.count != b.count { return a.count < b.count ? -1 : 1 }
                if a != b { return a < b ? -1 : 1 }
            } else if aNumeric != bNumeric {
                return aNumeric ? -1 : 1
            } else if a != b {
                return a < b ? -1 : 1
            }
        }
        if l.count == r.count { return 0 }
        return l.count < r.count ? -1 : 1
    }
}

// MARK: - 结果类型

/// 一次检查失败的原因。界面上只显示同一条「无法检查更新」，原因用于日志与测试。
enum UpdateCheckFailure: Error, Equatable {
    /// 应用自己的版本号读不出来（此时不发请求）
    case invalidCurrentVersion
    /// 离线、超时、DNS / TLS 失败等传输层错误
    case network
    /// 非 200 的 HTTP 状态
    case httpStatus(Int)
    /// 空响应、过大、不是预期的 JSON、缺字段、类型不对、draft / prerelease
    case invalidResponse
    /// `html_url` 不是 https://github.com 的链接，不能当作「打开发布页」的目标
    case untrustedReleaseURL
}

enum UpdateCheckResult: Equatable {
    /// 已是最新（当前版本 ≥ 最新发布也算）
    case upToDate(current: SemanticVersion)
    case updateAvailable(current: SemanticVersion, latest: SemanticVersion, releaseURL: URL)
    case failed(UpdateCheckFailure)
}

/// releases/latest 响应里用到的两个字段。
struct LatestRelease: Equatable {
    let version: SemanticVersion
    let pageURL: URL
}

// MARK: - 检查

enum UpdateChecker {
    /// 弹窗里展示、「复制命令」写入剪贴板的升级命令，不翻译。
    static let upgradeCommand = "brew upgrade --cask pixy"

    static let defaultEndpoint = URL(string: "https://api.github.com/repos/natinli/Pixy/releases/latest")!

    /// 单个请求的超时（秒）。
    static let timeout: TimeInterval = 10

    /// 响应体上限；真实的 releases/latest 响应只有几 KB。
    static let maxResponseBytes = 1_048_576

    // MARK: 仅 Debug 的地址覆盖

    #if DEBUG
    /// 仅 Debug：环境变量 `PIXY_UPDATE_URL` 覆盖请求地址，用于在本机起静态服务验证三条路径。
    /// Release 构建里这段代码与字符串都不存在。
    /// Debug only: lets a local static server stand in for GitHub. Compiled out of Release.
    private static var debugOverrideURL: URL? {
        guard let text = ProcessInfo.processInfo.environment["PIXY_UPDATE_URL"], !text.isEmpty else { return nil }
        return URL(string: text)
    }
    #endif

    /// 实际使用的请求地址。
    static var endpoint: URL {
        #if DEBUG
        if let override = debugOverrideURL { return override }
        #endif
        return defaultEndpoint
    }

    /// 是否放宽 `html_url` 校验、允许回环地址（只有 Debug 下设置了覆盖地址时才为真）。
    static var allowsLoopbackReleaseURL: Bool {
        #if DEBUG
        return debugOverrideURL != nil
        #else
        return false
        #endif
    }

    // MARK: 请求与会话

    /// 只设 `Accept`、`User-Agent: Pixy/<版本号>` 与固定的 `Accept-Language: en` 三个头：无鉴权、无 cookie、无 query、
    /// 无 body、无 build 号或任何用户 / 设备标识。
    /// Only `Accept`, `User-Agent: Pixy/<version>` and a fixed `Accept-Language: en` are set: no auth, cookies, query,
    /// body, build number or any user / device identifier.
    static func makeRequest(endpoint: URL, appVersion: SemanticVersion) -> URLRequest {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // 用解析后的主.次.修订（含预发布后缀），不带 +build 元数据
        request.setValue("Pixy/\(appVersion.description)", forHTTPHeaderField: "User-Agent")
        // 不设的话系统会自动附带用户的界面语言偏好（如 zh-CN,zh-Hans;q=0.9）；这个头去不掉，所以固定成所有用户一样的值，
        // 不泄露语言偏好。（空值会发出一个空头，不合 Accept-Language 的语法，所以不用空值。）
        // Left unset, the system adds the user's language preference (e.g. zh-CN,zh-Hans;q=0.9). The header cannot be
        // removed, so it is pinned to one value for everybody. (An empty value would send an invalid empty header.)
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        return request
    }

    /// 不落盘的会话配置：不存 cookie / 缓存 / 凭据，离线时立即失败而不是排队等网，总时长也有上限。
    static func makeSessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.waitsForConnectivity = false
        return config
    }

    static func makeSession() -> URLSession {
        URLSession(configuration: makeSessionConfiguration())
    }

    // MARK: 响应解析

    /// 解析 releases/latest 的响应体：取 `tag_name`（须是可解析的版本号）与 `html_url`（须是可信链接）。
    /// 空数据、超过 `maxResponseBytes`、不是 JSON 对象、缺字段或类型不对、draft / prerelease 为 true 均视为失败。
    static func parseLatestRelease(_ data: Data, allowLoopback: Bool = false) -> Result<LatestRelease, UpdateCheckFailure> {
        guard !data.isEmpty, data.count <= maxResponseBytes,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failure(.invalidResponse)
        }
        // latest 接口本不会返回草稿或预发布；防御性地拒绝
        for key in ["draft", "prerelease"] {
            if let flag = object[key] as? Bool, flag { return .failure(.invalidResponse) }
        }
        guard let tag = object["tag_name"] as? String, let version = SemanticVersion(tag),
              let pageText = object["html_url"] as? String, !pageText.isEmpty,
              let page = URL(string: pageText) else {
            return .failure(.invalidResponse)
        }
        guard isTrustedReleaseURL(page, allowLoopback: allowLoopback) else {
            return .failure(.untrustedReleaseURL)
        }
        return .success(LatestRelease(version: version, pageURL: page))
    }

    /// 「打开发布页」只会打开 https://github.com 下的链接（不带账号 / 端口），防止被篡改的响应诱导打开任意地址。
    /// `allowLoopback` 仅供 Debug 本机验证：额外允许 127.0.0.1 / localhost。
    static func isTrustedReleaseURL(_ url: URL, allowLoopback: Bool) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              components.user == nil, components.password == nil else { return false }
        if scheme == "https", host == "github.com", components.port == nil { return true }
        if allowLoopback, scheme == "http" || scheme == "https", host == "127.0.0.1" || host == "localhost" { return true }
        return false
    }

    // MARK: 一次检查

    /// 发出**一个** GET 请求并回调结果；无重试。回调在 URLSession 的后台队列（或全局队列）上，调用方自行切回主线程。
    /// `session` 由本次检查接管：请求发出后立即 `finishTasksAndInvalidate()`，所以每次检查传入一个新会话。
    /// 当前版本读不出来时不发请求，直接回调 `.failed(.invalidCurrentVersion)`（同样异步回调）。
    static func check(currentVersion: String?,
                      endpoint: URL = UpdateChecker.endpoint,
                      allowLoopbackReleaseURL: Bool = UpdateChecker.allowsLoopbackReleaseURL,
                      session: URLSession,
                      completion: @escaping (UpdateCheckResult) -> Void) {
        guard let currentText = currentVersion, let current = SemanticVersion(currentText) else {
            session.invalidateAndCancel()
            DispatchQueue.global(qos: .utility).async { completion(.failed(.invalidCurrentVersion)) }
            return
        }
        let request = makeRequest(endpoint: endpoint, appVersion: current)
        let task = session.dataTask(with: request) { data, response, error in
            completion(evaluate(current: current, data: data, response: response, error: error,
                                allowLoopback: allowLoopbackReleaseURL))
        }
        task.resume()
        session.finishTasksAndInvalidate()
    }

    /// 把一次请求的原始结果归为 `UpdateCheckResult`。
    static func evaluate(current: SemanticVersion, data: Data?, response: URLResponse?, error: Error?,
                         allowLoopback: Bool) -> UpdateCheckResult {
        if error != nil { return .failed(.network) }
        guard let http = response as? HTTPURLResponse else { return .failed(.invalidResponse) }
        guard http.statusCode == 200 else { return .failed(.httpStatus(http.statusCode)) }
        guard let data = data else { return .failed(.invalidResponse) }
        switch parseLatestRelease(data, allowLoopback: allowLoopback) {
        case .failure(let failure):
            return .failed(failure)
        case .success(let release):
            // 当前版本不低于最新发布（含更新的本地构建）一律算已是最新
            return release.version > current
                ? .updateAvailable(current: current, latest: release.version, releaseURL: release.pageURL)
                : .upToDate(current: current)
        }
    }
}
