Named S3 connections for captures and exports, opened by « S3 connections… » in Import and Export.
- **Kept**: name, endpoint, region, access key; secret only in your Keychain (AstroStack.S3), never shown again.
- **Endpoint**: https://host[:port]; http only on this Mac. Path-style for MinIO, Garage; region and bucket-name errors say the fix.
- **Two keys**: read-only for captures; for exports one writing only under its prefix (AWS: `s3:PutObject` on `arn:aws:s3:::bucket/exports/*`). An export never replaces an object nor writes into open projects' captures.
**Test** lists the bucket, answer shown as sent.
