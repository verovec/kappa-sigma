Named S3 connections for remote captures and exports.
- **Kept**: name, endpoint, region, access key in Settings; the secret only in your Keychain (AstroStack.S3), never shown again.
- **Endpoint**: https://host[:port]; http only on this Mac. Path-style on for MinIO and Garage, off for AWS.
- **Two keys**: read-only for captures; for exports one that may only write under its prefix (AWS: `s3:PutObject` on `arn:aws:s3:::bucket/exports/*`).
**Test** lists the bucket with these keys and shows the service's answer as sent.
