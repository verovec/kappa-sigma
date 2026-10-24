<p align="center">
  <img src="docs/assets/logo.svg" width="120" height="120" alt="Logo de Kappa-Sigma">
</p>

<h1 align="center">Kappa-Sigma</h1>

<p align="center">
  <strong>L'astrophotographie du ciel profond sur Mac, de la nuit brute à l'image finie.</strong><br>
  Empilez vos captures avec Siril, puis finissez-les dans un Studio aux aperçus Metal en temps réel :
  chaque réglage visible, expliqué, et à vous.
</p>

<p align="center">
  <a href="#démarrage-rapide">Démarrage rapide</a> &middot;
  <a href="#comment-ça-marche">Comment ça marche</a> &middot;
  <a href="#état">État</a> &middot;
  <a href="#technologies">Technologies</a> &middot;
  <a href="#documentation">Documentation</a><br>
  <a href="README.md">English</a> &middot; Français
</p>

<p align="center">
  <img alt="macOS 26" src="https://img.shields.io/badge/macOS-26-black?logo=apple">
  <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&amp;logoColor=white">
  <img alt="Metal" src="https://img.shields.io/badge/GPU-Metal-8A8A8A">
  <img alt="Licence MIT" src="https://img.shields.io/badge/licence-MIT-blue">
</p>

<p align="center">
  <img src="docs/assets/ngc7000.jpg" width="900" alt="La nébuleuse North America, NGC 7000, en Hα et OIII sur RVB">
  <br>
  <sub>NGC 7000, la nébuleuse North America : Hα et OIII sur RVB, capturée et empilée par l'auteur
  avec la chaîne que Kappa-Sigma remplace.</sub>
</p>

---

Une nuit de ciel profond laisse des centaines de brutes, de darks, de flats et d'offsets. En tirer
une image, c'est calibrer, écarter les mauvaises poses, aligner, empiler, puis étirer et colorer un
signal qui n'est presque que du bruit. Les outils existants cachent leurs décisions ou les noient
dans des centaines de panneaux.

**Kappa-Sigma** est une app macOS native qui mène une cible tout au long de ce parcours, du dossier
de capture au livrable. Siril fait les calculs sur les pixels, donc un empilement se reproduit à
l'octet près. Chaque verdict de l'app (une pose rejetée, un master choisi, une pose de référence)
est montré et peut être renversé, et aucun traitement ne change ses propres réglages en douce : la
valeur affichée est la valeur appliquée.

Le nom vient du kappa-sigma clipping, le rejet des valeurs aberrantes au cœur de tout empilement.

## Démarrage rapide

**Prérequis :** un Mac sous macOS 26 avec les Command Line Tools (Swift 6.2 ou plus récent) et
[`just`](https://github.com/casey/just). Siril 1.4 est nécessaire pour empiler ; GraXpert et
StarNet2 sont facultatifs. Xcode n'est pas requis.

```bash
git clone https://github.com/verovec/kappa-sigma.git && cd kappa-sigma
just setup      # installe swiftlint et le hook pre-push, puis vérifie l'hôte
just app-run    # construit AstroStack.app (debug) et l'ouvre
just app-run-release   # build optimisé pour les vrais runs (même chemin, remplace le debug)
```

La fenêtre de bienvenue liste vos projets récents et les outils hôtes trouvés (`just doctor` dit
la même chose depuis le terminal). **Nouveau projet…** crée un projet pour une cible ;
**Importer des captures…** lit un dossier de capture (sans jamais y écrire) et montre comment
chaque nuit sera calibrée ; suivez ensuite les étapes de la barre latérale, de l'empilement au
Studio puis à l'export.

## Comment ça marche

Un projet est un paquet `.astrostack` (une base SQLite et ses images). Sa fenêtre suit l'ordre
dans lequel travaille un astrophotographe :

```
  Données       nuits de capture, poses par filtre, couverture de calibration
     |
  Calibration   les masters de chaque série, leurs statistiques, les manques
     |
  Tri           métriques par pose, blink, garder ou rejeter, pose de référence
     |
  Empilement    les réglages d'empilement et le run Siril, avec son journal
     |
  Studio        étirement, raies d'émission, HDR, couleur, couche d'étoiles, en aperçu GPU
     |
  Export        les livrables
```

Chaque étape montre son état (à faire, prête, à regarder, faite) et vous passez librement de
l'une à l'autre : rien n'avance tout seul. Les captures, les masters et les résultats antérieurs
restent où ils sont, en lecture seule ; l'app n'écrit que dans ses projets.

## État

Kappa-Sigma empile et finit une cible de bout en bout ; il est validé sur les captures de M 31
(nuits large bande et dual-band) et d'IC 1848 de l'auteur, face à l'ancienne chaîne. Ce qui
marche aujourd'hui :

- Projets : la fenêtre de bienvenue (projets récents, outils hôtes), créer, enregistrer, rouvrir,
  et la barre du parcours avec l'état de chaque étape.
- Données et Calibration : un dossier de capture classé par nuit, filtre et type de pose ; le
  plan de calibration face à votre bibliothèque de masters, chaque verdict modifiable ; inspection
  et reconstruction d'un master.
- Tri : métriques par pose, blink, garder ou rejeter à un point d'arrêt après la notation, et une
  pose de référence d'alignement épinglée.
- Empilement : prétraitement d'une ou plusieurs nuits par Siril, séries large bande et dual-band,
  réglages simples et avancés sur le préréglage ; progression, journal, pause et reprise,
  annulation ; l'espace de travail nécessaire est vérifié avant le run, et ce qu'un run mort
  laisse derrière lui est nettoyé.
- Studio : aperçus GPU en direct de l'étirement (MTF, GHS, arcsinh), de la transformation
  d'histogramme, des courbes, de la saturation, de la désaturation du ciel, de la balance des
  couleurs, des écrans d'émission, du HDR, du débruitage et de la géométrie ; extraction de fond
  (GraXpert ou Siril), résolution astrométrique et calibration des couleurs (PCC, SPCC) par les
  outils hôtes ; un historique avec annulation, des pipelines avec points d'arrêt, et des profils.
- Export : séparation des étoiles avec StarNet2 et le jeu de livrables.
- Visionneuse : images FITS sur le GPU avec zoom, déplacement, étirement d'affichage automatique
  ou manuel, histogramme, lecture des pixels avec AD/Déc, surexpositions en surimpression et
  comparaison avant/après.
- Interface en anglais et en français, avec une fiche d'aide pour chaque étape et chaque
  traitement.

Limites connues : caméras couleur (OSC) seulement (le mono LRGB et les palettes bande étroite sont
prévus) ; pas de drizzle ; pas encore de build signé, l'app se construit depuis les sources avec
`just app-run`.

## Technologies

| Couche | Technologie | Emplacement |
|--------|-------------|-------------|
| Interface | SwiftUI et AppKit (app à documents) | `apps/macos/Sources/AstroStackApp` |
| Aperçus en temps réel | Noyaux Metal 3, chacun vérifié face à un oracle CPU | `RenderKit`, `ProcessKit` |
| Calcul d'image | Accelerate (vDSP, vImage), float32 planaire | `ImageKit`, `StackKit` |
| Prétraitement | Siril 1.4 piloté par tubes nommés | `StackKit` |
| Stockage des projets | SQLite via GRDB, migrations SQL versionnées | `ProjectKit` |
| Tests | Swift Testing, oracles enregistrés, suites live sur de vraies captures | `apps/macos/Tests` |

Swift 6 uniquement : pas de serveur, pas de binaire auxiliaire, pas de second langage. Détails dans
[Architecture](docs/architecture.md).

## Documentation

| Sujet | Où |
|-------|-----|
| Modules, outils hôtes, emplacement de vos données | [`docs/architecture.md`](docs/architecture.md) |
| Chaîne d'outils, recettes, tests, CI, conventions | [`docs/development.md`](docs/development.md) |
| Conception du produit et de l'architecture | [`docs/design/astrostack-macos.md`](docs/design/astrostack-macos.md) |
| Portes qualité et décisions du portage Swift | [`docs/engineering/swift-quality-playbook.md`](docs/engineering/swift-quality-playbook.md) |
| Tout le reste | [`docs/`](docs/README.md) |

La documentation détaillée est en anglais.

## Contribuer

Les tickets et les pull requests sont bienvenus. Lancez `just check` avant de pousser : c'est la
même porte que la CI (hygiène, lint, build de l'app, suite de tests complète). Les conventions de
la maison sont dans [`conventions/`](conventions/), et
[`docs/development.md`](docs/development.md) explique les tests, les oracles et les suites live.

## Licence

[MIT](LICENSE) © 2026 Clément Verove
