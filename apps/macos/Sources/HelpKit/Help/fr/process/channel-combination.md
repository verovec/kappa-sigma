Construit l’image RVB de travail à partir des couches du bundle : chaque canal reçoit une couche, avec un poids et un point noir (**poids · max(couche − noir, 0)**).
Les palettes RGB, HOO, SHO, HOS, Foraxx et LRGB remplissent les canaux ; une couche absente grise la palette, sans remplacement.
**L** remplace la luminance selon son opacité.
