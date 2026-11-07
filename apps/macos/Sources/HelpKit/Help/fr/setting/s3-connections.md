Connexions S3 nommées, pour captures distantes et exports.
- **Gardé** : nom, endpoint, région, clé d’accès dans les réglages, secret au trousseau (AstroStack.S3), jamais réaffiché.
- **Endpoint** : https://hôte[:port], http seulement sur ce Mac. Par chemin pour MinIO et Garage, pas AWS.
- **Deux clés** : lecture seule pour les captures, écriture seule sous un préfixe pour les exports (AWS : `s3:PutObject` sur `arn:aws:s3:::bucket/exports/*`). Sans voir l’existant, le service refuse tout remplacement.
**Tester** liste le bucket, réponse telle quelle. Jamais d’export sous un préfixe lu par un projet ouvert.
