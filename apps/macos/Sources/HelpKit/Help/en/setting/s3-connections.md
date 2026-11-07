Named S3 connections for remote captures and exports, also opened by « S3 connections… » in Import and Export.
- **Kept**: name, endpoint, region, access key; the secret only in your Keychain (AstroStack.S3).
- **Endpoint**: https://host[:port]; http on this Mac. Path-style for MinIO, Garage; without it, no dot in a bucket over https. Another region is named.
- **Two keys**: read-only for captures; for exports one writing only under its prefix (AWS: `s3:PutObject` on `arn:aws:s3:::bucket/exports/*`).
**Test** lists the bucket with these keys and shows the service's answer as sent.
