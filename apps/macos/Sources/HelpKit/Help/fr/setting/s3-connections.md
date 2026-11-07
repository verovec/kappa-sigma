Connexions S3 nommées pour les captures distantes et les exports.
- **Gardé** : nom, endpoint, région, clé d’accès dans les réglages ; le secret seulement dans votre trousseau (AstroStack.S3), jamais réaffiché.
- **Endpoint** : https://hôte[:port] ; http seulement sur ce Mac. Par chemin pour MinIO et Garage, pas pour AWS. Sans adressage par chemin, le nom du bucket doit être un nom d’hôte, sans point en https.
- **Région** : celle du bucket ; si c’en est une autre, la réponse nomme la bonne.
- **Deux clés** : lecture seule pour les captures ; pour les exports, une qui n’écrit que sous son préfixe (AWS : `s3:PutObject` sur `arn:aws:s3:::bucket/exports/*`).
**Tester** liste le bucket avec ces clés et montre la réponse du service telle quelle.
