Named S3 connections for remote captures and exports.
- **Kept**: name, endpoint, region, access key in Settings; the secret in your Keychain (AstroStack.S3), never shown again.
- **Endpoint**: https://host[:port]; http only on this Mac. Path-style for MinIO and Garage, not AWS.
- **Two keys**: read-only for captures; for exports, write-only under a prefix (AWS: `s3:PutObject` on `arn:aws:s3:::bucket/exports/*`). It cannot see existing files: the service is told never to replace one.
**Test** lists the bucket, answer shown as sent. No export goes into a prefix an open project reads captures from.
