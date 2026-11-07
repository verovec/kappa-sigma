Connexions S3 nommées : captures distantes et exports.
- **Gardé** : nom, endpoint, région, clé d’accès dans les réglages ; le secret au trousseau (AstroStack.S3), jamais réaffiché.
- **Endpoint** : https://hôte[:port] ; http seulement sur ce Mac. Par chemin pour MinIO et Garage, pas AWS.
- **Deux clés** : lecture seule pour les captures ; pour les exports, écriture sous son préfixe seulement (AWS : `s3:PutObject` sur `arn:aws:s3:::bucket/exports/*`).
**Tester** liste le bucket avec ces clés, réponse montrée telle quelle. Jamais d’export sous un préfixe lu par un projet ouvert.
