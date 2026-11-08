Connexions S3 nommées (captures, exports), aussi par « Connexions S3… » dans Import et Export.
- **Gardé** : nom, endpoint, région, clé d’accès ; le secret au trousseau (AstroStack.S3), jamais réaffiché.
- **Endpoint** : https://hôte[:port] ; http seulement sur ce Mac. Par chemin pour MinIO, Garage ; sinon sans point en https. Autre région nommée.
- **Deux clés** : lecture seule (captures) ; exports sous leur seul préfixe (AWS : `s3:PutObject` sur `arn:aws:s3:::bucket/exports/*`), jamais dans les captures d’un projet ouvert.
**Tester** liste le bucket avec ces clés, réponse telle quelle.
