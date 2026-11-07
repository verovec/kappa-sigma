Connexions S3 nommées pour captures distantes et exports, aussi par « Connexions S3… » dans Import et Export.
- **Gardé** : nom, endpoint, région, clé d’accès ; le secret seulement dans votre trousseau (AstroStack.S3).
- **Endpoint** : https://hôte[:port] ; http seulement sur ce Mac. Par chemin pour MinIO, Garage ; sinon sans point en https. Une autre région est nommée.
- **Deux clés** : lecture seule (captures) ; écriture limitée au préfixe (exports ; AWS : `s3:PutObject` sur `arn:aws:s3:::bucket/exports/*`).
**Tester** liste le bucket avec ces clés, réponse affichée telle quelle.
