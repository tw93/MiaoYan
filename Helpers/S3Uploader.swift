import CryptoKit
import Foundation
import Security

/// Where pasted images go when Image Upload is set to S3 / R2: any bucket
/// that speaks the S3 API (Cloudflare R2, Amazon S3, MinIO and the like),
/// written with a signed PUT so nobody has to install an uploader app.
struct S3UploadConfig: Equatable, Sendable {
    /// `https://<account>.r2.cloudflarestorage.com`; a path after the host is ignored.
    var endpoint = ""
    /// Blank means `auto`, which is what R2 takes.
    var region = ""
    var bucket = ""
    var accessKeyID = ""
    var secretAccessKey = ""
    /// The address the bucket is read from, `https://img.example.com`.
    var publicURL = ""

    /// Every field but Region filled, and an endpoint that names a host.
    var isComplete: Bool {
        endpointBase != nil
            && [bucket, accessKeyID, secretAccessKey, publicURL].allSatisfy { !$0.trimmed.isEmpty }
    }

    /// The region typed, else the one in an Amazon endpoint
    /// (`s3.eu-west-1.amazonaws.com`), else `auto`, which R2 takes.
    var signingRegion: String {
        if !region.trimmed.isEmpty { return region.trimmed }
        if let host = endpointBase?.host, host.hasSuffix(".amazonaws.com") {
            let labels = host.split(separator: ".").map(String.init).filter { $0 != "dualstack" }
            if let s3 = labels.firstIndex(where: { $0 == "s3" || $0.hasPrefix("s3-") }) {
                if labels[s3].hasPrefix("s3-") { return String(labels[s3].dropFirst(3)) }
                if s3 + 1 < labels.count - 2 { return labels[s3 + 1] }
            }
            return "us-east-1"
        }
        return "auto"
    }

    /// The endpoint's scheme, host and port; `https` when no scheme was typed,
    /// and no port when it is the scheme's own, which is not sent as Host.
    var endpointBase: URL? {
        let trimmed = endpoint.trimmed
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let parts = URLComponents(string: withScheme), let host = parts.host, !host.isEmpty else { return nil }
        var base = URLComponents()
        base.scheme = parts.scheme
        base.host = host
        let defaultPort = parts.scheme?.lowercased() == "http" ? 80 : 443
        base.port = parts.port == defaultPort ? nil : parts.port
        return base.url
    }

    /// Where an object written under `key` is read from.
    func publicLink(forKey key: String) -> String {
        var base = publicURL.trimmed
        if !base.contains("://") { base = "https://" + base }
        while base.hasSuffix("/") { base.removeLast() }
        return base + "/" + S3Signer.encodePath(key)
    }
}

/// AWS Signature Version 4 for S3, the scheme R2 and the other S3-compatible
/// stores accept.
enum S3Signer {
    static let algorithm = "AWS4-HMAC-SHA256"

    struct Credentials {
        var accessKeyID: String
        var secret: String
        var region: String
        var service = "s3"
    }

    /// Every byte but the RFC 3986 unreserved ones percent-encoded, `/` kept
    /// between segments, as S3 canonicalizes an object path.
    static func encodePath(_ path: String) -> String {
        var allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        allowed.insert("/")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(_ data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    static func signingKey(secret: String, date: String, region: String, service: String) -> SymmetricKey {
        func hmac(_ key: SymmetricKey, _ text: String) -> SymmetricKey {
            SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: key)))
        }
        var key = SymmetricKey(data: Data(("AWS4" + secret).utf8))
        for part in [date, region, service, "aws4_request"] {
            key = hmac(key, part)
        }
        return key
    }

    /// The `Authorization` header for a request with no query string.
    /// `headers` are the ones signed, `host` and `x-amz-date` among them;
    /// `path` is already encoded.
    static func authorization(method: String, path: String, headers: [String: String], payloadHash: String, credentials: Credentials) -> String {
        let lowered = Dictionary(headers.map { ($0.key.lowercased(), $0.value.trimmingCharacters(in: .whitespaces)) }, uniquingKeysWith: { $1 })
        let names = lowered.keys.sorted()
        let canonicalHeaders = names.map { "\($0):\(lowered[$0] ?? "")\n" }.joined()
        let signedHeaders = names.joined(separator: ";")
        let canonicalRequest = [method, path, "", canonicalHeaders, signedHeaders, payloadHash].joined(separator: "\n")
        let amzDate = lowered["x-amz-date"] ?? ""
        let date = String(amzDate.prefix(8))
        let scope = "\(date)/\(credentials.region)/\(credentials.service)/aws4_request"
        let stringToSign = [algorithm, amzDate, scope, sha256Hex(Data(canonicalRequest.utf8))].joined(separator: "\n")
        let key = signingKey(secret: credentials.secret, date: date, region: credentials.region, service: credentials.service)
        let signature = hex(HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key))
        return "\(algorithm) Credential=\(credentials.accessKeyID)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
    }

    static func amzDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }
}

enum S3Uploader {
    enum UploadError: LocalizedError {
        case incompleteSettings
        case invalidEndpoint
        /// The S3 error code only (`SignatureDoesNotMatch`): the body can
        /// carry the access key id, and this text reaches the diagnostics log.
        case rejected(status: Int, code: String)
        /// Uploaded, but the public URL does not serve it.
        case notPublic(status: Int)

        var errorDescription: String? {
            switch self {
            case .incompleteSettings: return "S3 upload settings are incomplete"
            case .invalidEndpoint: return "S3 endpoint is not a valid address"
            case .rejected(let status, let code): return "S3 upload failed with HTTP \(status) \(code)"
            case .notPublic(let status): return "The public URL answered HTTP \(status) for the uploaded image"
            }
        }

        static func code(in body: Data?) -> String {
            guard let text = body.flatMap({ String(data: $0, encoding: .utf8) }),
                let start = text.range(of: "<Code>"), let end = text.range(of: "</Code>", range: start.upperBound..<text.endIndex)
            else { return "" }
            return String(text[start.upperBound..<end.lowerBound].prefix(64))
        }
    }

    /// `2026/11/shot-1a2b3c4d.png`: a month per folder keeps a bucket
    /// browsable, and eight hex of the content's SHA-256 keep two different
    /// pictures with one name apart. A dropped file keeps its own name
    /// (`image.png`), and the local folder that kept names unique loses the
    /// file once it is uploaded, so the name alone let the next `image.png`
    /// overwrite the first in the bucket.
    static func objectKey(fileName: String, contentHash: String, date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = calendar.dateComponents([.year, .month], from: date)
        let name = fileName as NSString
        let ext = name.pathExtension
        let stem = name.deletingPathExtension + "-" + contentHash.prefix(8)
        return String(format: "%04d/%02d/", parts.year ?? 0, parts.month ?? 0) + (ext.isEmpty ? stem : stem + "." + ext)
    }

    static func contentType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "svg": return "image/svg+xml"
        case "bmp": return "image/bmp"
        case "tif", "tiff": return "image/tiff"
        default: return "application/octet-stream"
        }
    }

    /// The signed PUT that writes `body` under `key`, addressed path-style
    /// (`endpoint/bucket/key`), which R2 and MinIO need and S3 accepts.
    static func putRequest(config: S3UploadConfig, key: String, body: Data, contentType: String, date: Date) throws -> URLRequest {
        guard config.isComplete else { throw UploadError.incompleteSettings }
        guard let base = config.endpointBase, let host = base.host else { throw UploadError.invalidEndpoint }
        let bucket = config.bucket.trimmed
        let path = S3Signer.encodePath("/" + bucket + "/" + key)
        guard let url = URL(string: base.absoluteString + path) else { throw UploadError.invalidEndpoint }
        let hostHeader = base.port.map { "\(host):\($0)" } ?? host
        let payloadHash = S3Signer.sha256Hex(body)
        let amzDate = S3Signer.amzDate(date)
        let signed = ["host": hostHeader, "x-amz-content-sha256": payloadHash, "x-amz-date": amzDate]

        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(
            S3Signer.authorization(
                method: "PUT", path: path, headers: signed, payloadHash: payloadHash,
                credentials: S3Signer.Credentials(
                    accessKeyID: config.accessKeyID.trimmed,
                    secret: config.secretAccessKey.trimmed,
                    region: config.signingRegion)),
            forHTTPHeaderField: "Authorization")
        return request
    }

    /// Uploads the file with the saved settings and answers its public link,
    /// once that link serves it, or the error. Reading the Keychain and the
    /// file and hashing it run off the main thread.
    static func upload(fileAt fileURL: URL, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let config = S3UploadSettings.load()
            let key: String
            let request: URLRequest
            let body: Data
            do {
                body = try Data(contentsOf: fileURL)
                key = objectKey(fileName: fileURL.lastPathComponent, contentHash: S3Signer.sha256Hex(body), date: Date())
                request = try putRequest(config: config, key: key, body: body, contentType: contentType(forExtension: fileURL.pathExtension), date: Date())
            } catch {
                completion(.failure(error))
                return
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 120
            let session = URLSession(configuration: configuration)
            session.uploadTask(with: request, from: body) { data, response, error in
                if let error {
                    session.finishTasksAndInvalidate()
                    completion(.failure(error))
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status) else {
                    session.finishTasksAndInvalidate()
                    completion(.failure(UploadError.rejected(status: status, code: UploadError.code(in: data))))
                    return
                }
                // The local copy is trashed once the note links the upload, so
                // a public URL that does not serve it (a typo, the private API
                // host, a bucket without public access) must fail here first.
                let link = config.publicLink(forKey: key)
                guard let linkURL = URL(string: link) else {
                    session.finishTasksAndInvalidate()
                    completion(.failure(UploadError.notPublic(status: 0)))
                    return
                }
                var head = URLRequest(url: linkURL, timeoutInterval: 30)
                head.httpMethod = "HEAD"
                session.dataTask(with: head) { _, response, _ in
                    session.finishTasksAndInvalidate()
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    completion((200..<300).contains(status) ? .success(link) : .failure(UploadError.notPublic(status: status)))
                }.resume()
            }.resume()
        }
    }
}

/// The saved S3 / R2 settings: the secret in the Keychain, the rest in the
/// app's preferences.
enum S3UploadSettings {
    /// Per bundle id, so a `com.tw93.miaoyan.qa` build or a test run never
    /// reads or replaces the secret of the app in daily use.
    private static var keychainService: String { (Bundle.main.bundleIdentifier ?? "com.tw93.miaoyan") + ".s3-upload" }
    private static let keychainAccount = "secret-access-key"
    private enum Key {
        static let endpoint = "s3UploadEndpoint"
        static let region = "s3UploadRegion"
        static let bucket = "s3UploadBucket"
        static let accessKeyID = "s3UploadAccessKeyID"
        static let publicURL = "s3UploadPublicURL"
    }

    static func load() -> S3UploadConfig {
        let defaults = UserDefaults.standard
        return S3UploadConfig(
            endpoint: defaults.string(forKey: Key.endpoint) ?? "",
            region: defaults.string(forKey: Key.region) ?? "",
            bucket: defaults.string(forKey: Key.bucket) ?? "",
            accessKeyID: defaults.string(forKey: Key.accessKeyID) ?? "",
            secretAccessKey: readSecret() ?? "",
            publicURL: defaults.string(forKey: Key.publicURL) ?? "")
    }

    @discardableResult
    static func save(_ config: S3UploadConfig) -> Bool {
        let defaults = UserDefaults.standard
        defaults.set(config.endpoint.trimmed, forKey: Key.endpoint)
        defaults.set(config.region.trimmed, forKey: Key.region)
        defaults.set(config.bucket.trimmed, forKey: Key.bucket)
        defaults.set(config.accessKeyID.trimmed, forKey: Key.accessKeyID)
        defaults.set(config.publicURL.trimmed, forKey: Key.publicURL)
        return writeSecret(config.secretAccessKey.trimmed)
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: keychainAccount]
    }

    private static func readSecret() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeSecret(_ secret: String) -> Bool {
        let data = Data(secret.utf8)
        let update = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

extension String {
    /// Spaces and line breaks off both ends: a key pasted with its newline
    /// would otherwise sign wrong or break a header.
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
