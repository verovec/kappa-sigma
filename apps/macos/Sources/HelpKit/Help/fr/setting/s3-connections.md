Connexions S3 nommées, ouvertes par « Connexions S3… » dans Import et Export.
- **Gardé** : nom, endpoint, région, clé d’accès ; secret seulement au trousseau (AstroStack.S3), jamais réaffiché.
- **Endpoint** : https://hôte[:port] ; http seulement sur ce Mac. Par chemin pour MinIO, Garage ; les erreurs de région ou de bucket disent quoi changer.
- **Deux clés** : lecture seule (captures) ; exports : clé écrivant sous son seul préfixe (AWS : `s3:PutObject` sur `arn:aws:s3:::bucket/exports/*`), jamais dans des captures ouvertes.
**Tester** liste le bucket, réponse du service telle quelle.
