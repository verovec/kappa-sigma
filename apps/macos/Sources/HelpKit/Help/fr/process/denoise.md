Retire le bruit des données linéaires, avant l’étirement : chaque échelle (1, 2, 4 et 8 px) est seuillée à sa **force** en σ du bruit tel qu’il y apparaît.
Ce σ suit le **niveau de bruit**, proposé tel que mesuré sur l’image ; 0 ne retire rien.
**Quantité** 0 laisse l’image intacte ; 1 applique tout le résultat.
**Protéger les étoiles** garde ce qui dépasse le fond de 5 à 10 niveaux de bruit.
Les quantités en **luminance** et en **couleur** (avancé) dosent les deux parts.
