Connexions S3 nommées (captures distantes, exports), aussi par « Connexions S3… » dans Import et Export.
- **Gardé** : nom, endpoint, région, clé d’accès ; le secret au trousseau (AstroStack.S3), jamais réaffiché.
- **Endpoint** : https://hôte[:port] ; http seulement sur ce Mac. Par chemin pour MinIO et Garage, pas AWS.
- **Deux clés** : lecture seule pour les captures ; pour les exports, écriture sous son préfixe seulement (AWS : `s3:PutObject` sur `arn:aws:s3:::bucket/exports/*`), jamais dans les captures d’un projet ouvert.
**Tester** liste le bucket avec ces clés, réponse brute affichée.
