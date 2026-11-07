# RemoteKit

A minimal S3 client in Swift (card 0149, epic E24): the calls AstroStack needs against any
S3-compatible endpoint (AWS, MinIO, Scaleway, Backblaze B2, Cloudflare R2, Garage). It is a leaf
module (Foundation and CryptoKit only), with no AWS SDK and no helper process.

## Entry points

- `S3Endpoint(url:region:addressing:)` is scheme, host and port, plus `.pathStyle` (MinIO,
  Garage) or `.virtualHost` (AWS, R2, Scaleway). It throws `S3Error.invalidEndpoint` on a URL
  that is not `http(s)://host[:port]`.
- `S3Credentials` is the access key, the secret and an optional STS session token. It is a value
  only: storing it (the Keychain) is card 0150's job.
- `S3Client(endpoint:credentials:transport:)` offers:
  - `list(bucket:prefix:)`: ListObjectsV2, every page.
  - `head(bucket:key:)`: `nil` on 404.
  - `get(bucket:key:range:)`: an inclusive byte range.
  - `download(bucket:key:to:expect:progress:)`: written to `<to>.part`, verified, then renamed.
  - `upload(file:bucket:key:progress:)`: one PUT below 64 MiB, multipart in 16 MiB parts above.
  - `delete(bucket:key:)`.
- `HTTPTransport.urlSession()` is the live network. Tests build an `HTTPTransport` from two
  closures (`Tests/RemoteKitTests/Fake.swift`).
- `SigV4` is the signer, a pure function of request, credentials and date. It is pinned by the
  AWS SigV4 test suite (`Tests/RemoteKitTests/Fixtures/sigv4/`, Apache-2.0, see its `NOTICE`).

## Rules it keeps

- Errors are shown as the service sent them: `S3Error.service` keeps the status, `<Code>`,
  `<Message>` and request id (R2).
- Only 500/502/503/504 answers (never a 501), timeouts and the transient codes (`InternalError`, `ServiceUnavailable`,
  `SlowDown`, also when CompleteMultipartUpload sends them inside a 200) are retried: 3 tries,
  backoff 500 ms then 1 s, each retry reported through `progress`. A 4xx is never retried. Every
  try is signed again; a body is hashed once.
- Downloads check the size and ETag against the listing (`expect`). They check the content against
  a full-object `x-amz-checksum-sha256` (asked for with `x-amz-checksum-mode: ENABLED`), or else a
  single-part ETag (its MD5, unless SSE-KMS or SSE-C). A composite checksum (`…-N`) leaves the
  size as the only check. A failure or a cancellation leaves neither the file nor its `.part`; an
  existing file is replaced atomically.
- Bytes are read as stored (`Accept-Encoding: identity`). A ranged read answered 200 (Range
  ignored) is an error, and so is a truncated listing without a continuation token: never a
  partial answer passed off as whole.
- Uploads label the object `application/octet-stream` unless the caller names a type. A file's
  size is read through symbolic links (lanes link their frames).
- A retried CompleteMultipartUpload that finds `NoSuchUpload` (the first answer was lost) checks
  the object with HEAD: same size and part count is success, anything else stays the error.
- Listings ask for `encoding-type=url` and decode keys (`+` is a space), so a key XML cannot carry
  survives. Leading whitespace before `<?xml` (S3's keep-alive) is skipped.
- Redirects are refused (`RedirectRefusal`): a 3xx such as `PermanentRedirect` is an error, never a
  signed request replayed to another host. A 3xx or 400 naming another `x-amz-bucket-region` than
  the connection's, or one its host does not serve, is `S3Error.wrongRegion`: the service's answer
  as sent, then the region and what to change (a 400 only with a region code, so a 400
  `RequestTimeout` stays retried).
- Every request is bounded (`HTTPTransport.configuration()`): 60 s without bytes (`idleTimeout`,
  retried as a timeout) and 6 h in all (`transferTimeout`, a 4 GB object at 200 kB/s), which ends
  in `S3Error.transferTimedOut` and is never retried: a new try would start from byte 0.
- A bucket name the endpoint cannot address is refused before anything is sent
  (`S3Endpoint.validate(bucket:)`, `S3Error.invalidBucket`): virtual-host needs a host name, with
  no dot over https; path-style only refuses an empty name or a `/`.
- `S3Credentials` print redacted (last 4 characters of the access key, never the secret or the
  token), so credentials, a signer or a client can be printed whole. The signed wire request
  (`HTTPRequest`) carries `Authorization` and `x-amz-security-token` as sent: never log it.
- Uploads send `x-amz-checksum-sha256` on every body, so the service refuses a corrupted part.
  A failed or cancelled multipart upload is aborted from a fresh task, because a cancelled task's
  requests fail at once.
- Keys are percent-encoded once and never normalised (S3's rule, not the generic AWS one). The
  URL sent carries exactly the encoding that was signed.

## Not supported

- SSE-C (customer-provided keys) and presigned URLs.
- Bucket management, except the live test's own bucket creation.
- `URLSession` background sessions: the app is not sandboxed and transfers in the foreground.
- Streaming progress inside one download: the live transport reports once, when the body is
  complete (`total` is 0 when no listed size is passed). Uploads report per part.
- Retrying CreateMultipartUpload after a timeout can leave the first try's upload behind, never
  aborted: give buckets an `AbortIncompleteMultipartUpload` lifecycle rule.
- One `HTTPTransport.urlSession()` per connection, kept for its life: each call makes a URLSession
  that is never invalidated.
- Parallel parts: parts go one after another; card 0155 measures before adding concurrency.
- Verifying multipart objects end to end. Their ETag is not a content hash and their SHA-256 is
  composite. Card 0152 (exports) compares its own SHA-256.

## Tests

- `swift test --filter RemoteKitTests`: signer vectors, addressing, client behaviour over a
  scripted transport, and the URLSession transport over a stub `URLProtocol`. No network.
- `just s3-live`: `LiveS3Tests` against a local `minio server` you start yourself. It uploads
  70 MiB, then lists, heads, reads a range, downloads and deletes under a random prefix. It skips
  without `ASTROSTACK_S3_LIVE_ENDPOINT`.

## Extending

A new S3 call is an `S3Request` (method, bucket, key, query, headers, body) sent through
`perform`, which signs and retries it. Parse its answer with `XMLNode`. Add a scripted-transport
test beside the others, and a step in `LiveS3Tests` when MinIO can answer it.
