import XCTest

@testable import MiaoYan

/// The expected values are the worked examples in AWS's Signature Version 4
/// documentation, so a signer that only agrees with itself fails here.
final class S3UploaderTests: XCTestCase {
    private let exampleKeyID = "AKIAIOSFODNN7EXAMPLE"
    private let exampleSecret = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    private var awsExample: S3Signer.Credentials { S3Signer.Credentials(accessKeyID: exampleKeyID, secret: exampleSecret, region: "us-east-1") }

    func testSigningKeyMatchesAWSExample() {
        let key = S3Signer.signingKey(secret: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY", date: "20120215", region: "us-east-1", service: "iam")
        XCTAssertEqual(key.withUnsafeBytes { S3Signer.hex($0) }, "f4780e2d9f65fa895f9c67b32ce1baf0b0d8a43505a000a1a9e090d414db404d")
    }

    func testGetObjectSignatureMatchesAWSExample() {
        let auth = S3Signer.authorization(
            method: "GET", path: "/test.txt",
            headers: [
                "Host": "examplebucket.s3.amazonaws.com",
                "Range": "bytes=0-9",
                "x-amz-content-sha256": S3Signer.sha256Hex(Data()),
                "x-amz-date": "20130524T000000Z",
            ],
            payloadHash: S3Signer.sha256Hex(Data()), credentials: awsExample)
        XCTAssertEqual(
            auth,
            "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, "
                + "SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, "
                + "Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
    }

    func testPutObjectSignatureMatchesAWSExample() {
        let body = Data("Welcome to Amazon S3.".utf8)
        let hash = S3Signer.sha256Hex(body)
        XCTAssertEqual(hash, "44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072")
        let path = S3Signer.encodePath("/test$file.text")
        XCTAssertEqual(path, "/test%24file.text")
        let auth = S3Signer.authorization(
            method: "PUT", path: path,
            headers: [
                "Date": "Fri, 24 May 2013 00:00:00 GMT",
                "Host": "examplebucket.s3.amazonaws.com",
                "x-amz-date": "20130524T000000Z",
                "x-amz-storage-class": "REDUCED_REDUNDANCY",
                "x-amz-content-sha256": hash,
            ],
            payloadHash: hash, credentials: awsExample)
        XCTAssertTrue(auth.hasSuffix("Signature=98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd"), auth)
    }

    private var r2: S3UploadConfig {
        S3UploadConfig(
            endpoint: " https://abc123.r2.cloudflarestorage.com/notes-bucket/ ",
            accessKeyID: exampleKeyID, secretAccessKey: exampleSecret, publicURL: "img.example.com/")
    }

    func testThePutGoesPathStyleToTheBucketAndIsSigned() throws {
        let date = Date(timeIntervalSince1970: 1_764_115_200)  // 2025-11-26 00:00 UTC
        let key = S3Uploader.objectKey(fileName: "截图 1.png", contentHash: S3Signer.sha256Hex(Data([1, 2, 3])), date: date)
        XCTAssertEqual(key, "2025/11/截图 1-039058c6.png")
        let request = try S3Uploader.putRequest(config: r2, key: key, body: Data([1, 2, 3]), contentType: "image/png", date: date)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://abc123.r2.cloudflarestorage.com/notes-bucket/2025/11/%E6%88%AA%E5%9B%BE%201-039058c6.png")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/png")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-amz-date"), "20251126T000000Z")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-amz-content-sha256"), S3Signer.sha256Hex(Data([1, 2, 3])))
        let auth = try XCTUnwrap(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(auth.hasPrefix("AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20251126/auto/s3/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature="), auth)
    }

    func testThePublicLinkJoinsTheAddressAndTheKey() {
        XCTAssertEqual(r2.publicLink(forKey: "2025/11/截图 1.png"), "https://img.example.com/2025/11/%E6%88%AA%E5%9B%BE%201.png")
        var withScheme = r2
        withScheme.publicURL = "http://pub-1.r2.dev//"
        XCTAssertEqual(withScheme.publicLink(forKey: "a.png"), "http://pub-1.r2.dev/a.png")
    }

    /// A dropped file keeps its own name and the local copy goes once it is
    /// uploaded, so a second `image.png` took the first one's key and
    /// replaced it in the bucket under every note that linked it.
    func testTwoPicturesWithOneNameGetTwoKeys() {
        let date = Date(timeIntervalSince1970: 1_764_115_200)
        let first = S3Uploader.objectKey(fileName: "image.png", contentHash: S3Signer.sha256Hex(Data("one".utf8)), date: date)
        let second = S3Uploader.objectKey(fileName: "image.png", contentHash: S3Signer.sha256Hex(Data("two".utf8)), date: date)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(S3Uploader.objectKey(fileName: "README", contentHash: "abcdef0123", date: date), "2025/11/README-abcdef01")
    }

    /// R2 shows the bucket's S3 API address with the bucket at its end, and
    /// Amazon puts it at the front of the host; both are typed as one field.
    func testTheBucketComesFromTheAddress() throws {
        func parsed(_ endpoint: String) -> (bucket: String?, base: String?) {
            let config = S3UploadConfig(endpoint: endpoint)
            return (config.bucket, config.endpointBase?.absoluteString)
        }
        XCTAssertEqual(parsed("https://abc.r2.cloudflarestorage.com/notes").bucket, "notes")
        XCTAssertEqual(parsed("https://abc.r2.cloudflarestorage.com/notes").base, "https://abc.r2.cloudflarestorage.com")
        XCTAssertEqual(parsed("http://127.0.0.1:9000/photos/").bucket, "photos")
        XCTAssertEqual(parsed("my.photos.s3.eu-west-1.amazonaws.com").bucket, "my.photos")
        XCTAssertEqual(parsed("my.photos.s3.eu-west-1.amazonaws.com").base, "https://s3.eu-west-1.amazonaws.com")
        XCTAssertEqual(parsed("https://s3.eu-west-1.amazonaws.com/photos").bucket, "photos")
        XCTAssertNil(parsed("https://abc.r2.cloudflarestorage.com").bucket)
        XCTAssertNil(parsed("https://s3.amazonaws.com").bucket)

        let request = try S3Uploader.putRequest(
            config: S3UploadConfig(endpoint: "photos.s3.eu-west-1.amazonaws.com", accessKeyID: "k", secretAccessKey: "s", publicURL: "img.example.com"),
            key: "a.png", body: Data(), contentType: "image/png", date: Date(timeIntervalSince1970: 1_764_115_200))
        XCTAssertEqual(request.url?.absoluteString, "https://s3.eu-west-1.amazonaws.com/photos/a.png")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.contains("/eu-west-1/s3/aws4_request") == true)
    }

    func testTheRegionComesFromTheAddress() {
        func region(_ endpoint: String) -> String { S3UploadConfig(endpoint: endpoint).signingRegion }
        XCTAssertEqual(region("https://abc.r2.cloudflarestorage.com/notes"), "auto")
        XCTAssertEqual(region("https://abc.eu.r2.cloudflarestorage.com/notes"), "auto")
        XCTAssertEqual(region("s3.eu-west-1.amazonaws.com/photos"), "eu-west-1")
        XCTAssertEqual(region("photos.s3.dualstack.ap-northeast-1.amazonaws.com"), "ap-northeast-1")
        XCTAssertEqual(region("https://s3-us-west-2.amazonaws.com/photos"), "us-west-2")
        XCTAssertEqual(region("https://s3.amazonaws.com/photos"), "us-east-1")
        XCTAssertEqual(region("https://s3.us-west-004.backblazeb2.com/photos"), "us-west-004")
        XCTAssertEqual(region("http://127.0.0.1:9000/photos"), "us-east-1")
        XCTAssertEqual(region("https://s3-proxy.corp.com/photos"), "us-east-1")
        XCTAssertEqual(region("https://s3.files.corp.com/photos"), "us-east-1")
        XCTAssertEqual(region("https://s3.us-gov-west-1.amazonaws.com/photos"), "us-gov-west-1")
    }

    /// A port the scheme implies is not sent as Host, so it is not signed either.
    func testADefaultPortIsLeftOutAndAnotherKept() {
        XCTAssertEqual(S3UploadConfig(endpoint: "https://minio.local:443/").endpointBase?.absoluteString, "https://minio.local")
        XCTAssertEqual(S3UploadConfig(endpoint: "http://127.0.0.1:9000").endpointBase?.absoluteString, "http://127.0.0.1:9000")
        XCTAssertNil(S3UploadConfig(endpoint: "https://").endpointBase)
    }

    func testAKeyPastedWithItsNewlineStillSigns() throws {
        var pasted = r2
        pasted.accessKeyID = exampleKeyID + "\n"
        pasted.secretAccessKey = exampleSecret + "\n"
        let date = Date(timeIntervalSince1970: 1_764_115_200)
        XCTAssertEqual(
            try S3Uploader.putRequest(config: pasted, key: "a.png", body: Data(), contentType: "image/png", date: date).value(forHTTPHeaderField: "Authorization"),
            try S3Uploader.putRequest(config: r2, key: "a.png", body: Data(), contentType: "image/png", date: date).value(forHTTPHeaderField: "Authorization"))
    }

    /// The error goes to the diagnostics log, and S3's body can name the
    /// access key id, so only its code is kept.
    func testARefusalKeepsTheErrorCodeAndNotTheBody() {
        let body = Data("<Error><Code>SignatureDoesNotMatch</Code><AWSAccessKeyId>AKIAIOSFODNN7EXAMPLE</AWSAccessKeyId></Error>".utf8)
        let error = S3Uploader.UploadError.rejected(status: 403, code: S3Uploader.UploadError.code(in: body))
        XCTAssertEqual(error.errorDescription, "S3 upload failed with HTTP 403 SignatureDoesNotMatch")
        XCTAssertEqual(S3Uploader.UploadError.code(in: Data("not xml".utf8)), "")
    }

    func testSettingsAreCompleteWithFourFields() {
        XCTAssertTrue(r2.isComplete)
        XCTAssertEqual(r2.signingRegion, "auto")
        var noBucket = r2
        noBucket.endpoint = "https://abc123.r2.cloudflarestorage.com"
        XCTAssertFalse(noBucket.isComplete, "Save stays off until the address names a bucket")
        var missing = r2
        missing.secretAccessKey = " \n"
        XCTAssertFalse(missing.isComplete)
        var noHost = r2
        noHost.endpoint = "https://"
        XCTAssertFalse(noHost.isComplete, "Save stays off for an endpoint naming no host")
        XCTAssertThrowsError(try S3Uploader.putRequest(config: missing, key: "a.png", body: Data(), contentType: "image/png", date: Date()))
    }

    @MainActor
    func testOnlyImagesGoToTheBucket() {
        XCTAssertEqual(ClipboardManager.uploadHost(forAttachmentAt: "/i/shot.png", setting: "S3"), .s3)
        XCTAssertNil(ClipboardManager.uploadHost(forAttachmentAt: "/files/report.pdf", setting: "S3"))
    }
}
