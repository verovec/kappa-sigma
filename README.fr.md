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
  <a href="#ce-qui-marche-aujourdhui">Ce qui marche aujourd'hui</a> &middot;
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
  <sub>NGC 7000, la nébuleuse North America : Hα et OIII sur RVB.</sub>
</p>

---

Une nuit de ciel profond laisse des centaines de brutes, de darks, de flats et d'offsets. En tirer
une image, c'est calibrer, écarter les mauvaises poses, aligner, empiler, puis étirer et colorer un
signal qui n'est presque que du bruit. Les outils existants cachent leurs décisions ou les noient
dans des centaines de panneaux.

**Kappa-Sigma** est une app macOS native qui mène une cible du dossier de capture à l'image finie :

- **Reproductible.** Siril fait les calculs sur les pixels : mêmes poses et mêmes réglages, même
  empilement, à l'octet près.
- **Rien de caché.** Chaque verdict (une pose rejetée, un master choisi, une pose de référence) est
  montré et peut être renversé.
- **La valeur affichée est la valeur appliquée.** Aucun traitement ne mesure l'image pour changer
  ses propres réglages en douce ; une mesure ne remplit jamais qu'une suggestion.
- **Vos données restent à vous.** Captures, masters et résultats antérieurs sont en lecture seule ;
  l'app n'écrit que dans ses projets.

Le nom vient du kappa-sigma clipping, le rejet des valeurs aberrantes au cœur de tout empilement.

## Démarrage rapide

**Prérequis :** un Mac sous macOS 26 avec les Command Line Tools (Swift 6.2 ou plus récent) et
[`just`](https://github.com/casey/just). Xcode n'est pas requis.

| Outil hôte | Sert à |
|------------|--------|
| [Siril](https://siril.org) 1.4 | Empilement, résolution astrométrique, calibration des couleurs (requis) |
| [GraXpert](https://graxpert.com) | Extraction de fond (facultatif, Siril sait aussi le faire) |
| [StarNet2](https://www.starnetastro.com) | Séparation des étoiles à l'export (facultatif) |

Un outil absent grise les traitements qui en ont besoin, avec une fiche d'installation ; rien ne
bascule en silence sur un autre algorithme.

```bash
git clone https://github.com/verovec/kappa-sigma.git && cd kappa-sigma
just setup                              # installe swiftlint et le hook pre-push, vérifie l'hôte
just app-build -c release               # construit AstroStack.app optimisée
open -n apps/macos/.build/AstroStack.app
```

Utilisez le build release pour les vraies nuits : empilement et aperçus sont bien plus rapides.
Pour développer, `just app-run` construit un bundle debug au même chemin et l'ouvre (il remplace
le release, et inversement). `just doctor` fait le point sur la chaîne d'outils, les outils hôtes
et les dossiers de données depuis le terminal.

## Comment ça marche

La fenêtre de bienvenue liste vos projets récents et les outils hôtes trouvés. **Nouveau projet…**
crée un projet pour une cible ; **Importer des captures…** lit un dossier de capture (sans jamais y
écrire) et montre comment chaque nuit sera calibrée. Un projet est un paquet `.astrostack` (une
base SQLite et ses images), et sa barre latérale suit l'ordre dans lequel travaille un
astrophotographe :

```
  Données       nuits de capture, poses par filtre, temps d'intégration, couverture de calibration
     |
  Calibration   les masters de chaque série, leurs statistiques, les manques
     |
  Tri           métriques par pose, blink, garder ou rejeter, pose de référence
     |
  Empilement    les réglages par voie et le run Siril, avec son journal
     |
  Studio        étirement, raies d'émission, HDR, couleur, étoiles, en aperçu GPU
     |
  Export        séparation des étoiles et livrables
```

Chaque étape montre son état (à faire, prête, à regarder, faite) et vous passez librement de
l'une à l'autre : rien n'avance tout seul.

## Ce qui marche aujourd'hui

Le parcours complet tourne de bout en bout. Il est validé sur les captures de M 31 (nuits large
bande et dual-band) et d'IC 1848 de l'auteur, face à l'ancienne chaîne qu'il remplace.

| Étape | Ce que vous pouvez faire |
|-------|--------------------------|
| **Données** | Classer un dossier de capture par nuit, filtre et type de pose ; ajouter une nuit plus tard et relire ; voir, élaguer et supprimer les empilements jamais exportés. |
| **Calibration** | Associer chaque série à votre bibliothèque de masters par nuit, chaque verdict modifiable ; inspecter et reconstruire un master. |
| **Tri** | Noter chaque pose, les faire défiler en blink, garder ou rejeter à un point d'arrêt, épingler la référence d'alignement ; double-cliquer une pose pour l'ouvrir dans la visionneuse. |
| **Empilement** | Runs d'une ou plusieurs nuits par Siril, voies large bande et dual-band, réglages simples et avancés par voie, un run par objet ; progression, journal, pause, reprise après réouverture, annulation. L'espace de travail est vérifié avant le run, et ce qu'un run mort laisse derrière lui est nettoyé. |
| **Studio** | Aperçus GPU en direct de l'étirement (MTF, GHS, arcsinh), des niveaux, des courbes, de la saturation, de la désaturation du ciel, de la balance des couleurs, des écrans d'émission, de l'injection de raies Hα / OIII, du HDR, du débruitage et de la géométrie (recadrage, rotation, miroir). Extraction de fond (GraXpert ou Siril), résolution astrométrique et calibration des couleurs (PCC ou SPCC) par les outils hôtes. Basculer entre l'image combinée et la branche de chaque canal ; un historique par couche avec annulation ; pipelines avec points d'arrêt et rejeu ; profils ; masques. |
| **Export** | Séparation des étoiles avec StarNet2 et jeu de livrables, avec la recette qui l'a produit. |

Dans toute l'app :

- **Visionneuse :** images FITS sur le GPU avec zoom, déplacement, plein écran, étirement
  d'affichage automatique ou manuel, histogramme qui dit quelle image il compte, lecture des pixels
  avec AD/Déc, surexpositions en surimpression et comparaison avant/après.
- **Objets du ciel :** un catalogue tiré des listes de Siril, cherchable par n'importe quel alias,
  affiché dans la barre latérale et proposé à la résolution astrométrique.
- **Aide :** une fiche pour chaque étape, traitement et réglage, qui explique chaque valeur par
  défaut.
- **Clavier :** plein écran (⇧⌘F), zoom (⌘= / ⌘-), rotation et miroir, afficher ou masquer le
  panneau Présentation (⌥⌘0), un seul ⌘Z pour tout un run de pipeline.
- **Langues :** anglais et français.

**Limites connues :** caméras couleur (OSC) seulement (le mono LRGB et les palettes bande étroite
sont prévus) ; pas de drizzle ; pas encore de build signé, l'app se construit depuis les sources.

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
