Connexions S3 nommées pour captures distantes et exports, aussi par « Connexions S3… » dans Import et Export.
- **Gardé** : nom, endpoint, région, clé d’accès ; le secret seulement dans votre trousseau (AstroStack.S3), jamais réaffiché.
- **Endpoint** : https://hôte[:port] ; http seulement sur ce Mac. Par chemin pour MinIO et Garage, pas AWS.
- **Deux clés** : lecture seule pour les captures ; pour les exports, une n’écrivant que sous son préfixe (AWS : `s3:PutObject` sur `arn:aws:s3:::bucket/exports/*`).
**Tester** liste le bucket avec ces clés, réponse affichée telle quelle.
