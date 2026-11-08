Named S3 connections for remote captures and exports; also « S3 connections… » in Import and Export.
- **Kept**: name, endpoint, region, access key; the secret in your Keychain (AstroStack.S3), never shown again.
- **Endpoint**: https://host[:port]; http only on this Mac. Path-style for MinIO, Garage; otherwise no dot in an https bucket. Another region is named.
- **Two keys**: read-only for captures; for exports one writing only under its prefix (AWS: `s3:PutObject` on `arn:aws:s3:::bucket/exports/*`), never into open projects' captures.
**Test** lists the bucket with these keys, answer shown as sent.
