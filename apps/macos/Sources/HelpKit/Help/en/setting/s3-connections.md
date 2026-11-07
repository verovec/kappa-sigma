Named S3 connections for remote captures and exports, also opened by « S3 connections… » in Import and Export.
- **Kept**: name, endpoint, region, access key; the secret only in your Keychain (AstroStack.S3), never shown again.
- **Endpoint**: https://host[:port]; http only on this Mac. Path-style for MinIO and Garage, not AWS.
- **Two keys**: read-only for captures; for exports one writing only under its prefix (AWS: `s3:PutObject` on `arn:aws:s3:::bucket/exports/*`). An export never replaces an object, nor writes into an open project's captures.
**Test** lists the bucket, answer shown as sent.
