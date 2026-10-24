# Playbook qualité Swift — comment on garde le code propre et sans régression (E10–E19)

*Rédigé le 2026-10-20 à partir d'une revue des recommandations publiées en 2025–2026 (Apple,
swift.org, Swift Evolution, swift-testing, GitHub, auteurs reconnus). Chaque règle cite sa source.
Les points que les sources ne tranchent pas sont marqués **à vérifier**. Les règles opérationnelles
courtes vivent dans `conventions/swift-conventions.md` et `conventions/testing-conventions.md` ;
ce document explique le **pourquoi** et le **où** (quelle carte applique quoi).*

## 0. Les dix décisions

| # | Décision | Pourquoi (résumé) | Carte |
|---|---|---|---|
| 1 | `swift-tools-version: 6.2`, Swift 6 strict, **Approachable Concurrency** activée partout | Apple : « nous recommandons à tous les projets d'adopter ce réglage » (WWDC25 268) | 0040 |
| 2 | `AstroStackApp` isolé `MainActor` par défaut ; **les kits restent `nonisolated`** | Apple : MainActor par défaut « pour le module app et les modules UI », `nonisolated` « pour les bibliothèques » | 0040 |
| 3 | Non-`Sendable` d'abord ; `actor` seulement pour un état partagé mesuré | Massicotte : « beaucoup de Sendable = trop de frontières d'isolation » | tous |
| 4 | Calcul lourd `async` marqué `@concurrent` | Avec SE-0461 un `nonisolated async` tourne sur l'acteur appelant : une pile appelée depuis l'UI bloquerait le main thread | 0041, 0048, 0066 |
| 5 | Warnings = erreurs (`.treatAllWarnings(as: .error)`), `package` plutôt que `@testable` | SE-0480 ; l'équipe Swift décourage `@testable` (bugs non maintenus, dépréciation envisagée) | 0040 |
| 6 | **Metal 3** maintenant, Metal 4 en option plus tard ; fast-math **désactivé** ; `.metallib` via Xcode, `makeLibrary(source:)` en repli | SwiftPM ne compile pas les `.metal` avec `swift build` (bug ouvert #7716) ; fast-math casse la parité CPU/GPU | 0042 |
| 7 | Document = `NSDocument` (AppKit) autour d'un paquet `.astrostack` ; **GRDB 7** pour `project.db` | `FileWrapper` + SQLite = copie à chaque snapshot ; GRDB 7 est Swift 6 strict, WAL, migrations | 0040, 0068 |
| 8 | Processus externes via **swift-subprocess 1.0** | Structured concurrency, teardown SIGTERM→SIGKILL, descripteurs de FIFO passés tels quels | 0045 |
| 9 | Tests : Swift Testing, suites live préfixées `Live` + `ConditionTrait`, tolérances explicites, pas de bits sur le GPU | Pas de filtrage par tag en CLI avant Swift 6.4 ; parité GPU/CPU n'est jamais bit-exacte | tous |
| 10 | CI hébergée `macos-26` **sur PR seulement**, cache `.build`, garde Metal Toolchain ; perf et parité serrée en local | Minutes macOS facturées ×10 : ~200 min/mois sur un dépôt privé Free | 0040 |

---

## 1. Concurrence Swift 6.2+ (ce qui a changé depuis les conventions initiales)

**Règle de progression (Apple, WWDC25 « Embracing Swift concurrency »)** : code main-actor →
`async` pour la latence → `@concurrent` pour le CPU → `actor` seulement « quand garder la donnée
sur le main actor fait tourner trop de code sur le main thread ». Les modèles « devraient en général
être sur le main actor avec l'UI, ou rester non-Sendable ».
https://developer.apple.com/videos/play/wwdc2025/268/

**Isolation par défaut, par cible** (`Package.swift`) :

```swift
// AstroStackApp (et toute cible qui ne contient que des vues / view models)
swiftSettings: [
  .swiftLanguageMode(.v6),
  .defaultIsolation(MainActor.self),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),   // SE-0461
  .enableUpcomingFeature("InferIsolatedConformances"),        // SE-0470
  .treatAllWarnings(as: .error),                               // SE-0480
]
// ImageKit, RenderKit, ProcessKit, ProjectKit, StackKit, HelpKit : même liste SANS defaultIsolation
```

Sources : https://useyourloaf.com/blog/approachable-concurrency-in-swift-packages/ ,
https://www.donnywals.com/exploring-concurrency-changes-in-swift-6-2/ . **Désaccord** : Massicotte
reste sur `nonisolated` par défaut partout (https://www.massicotte.org/default-isolation-swift-6_2/) ;
fatbobman documente des pièges (macros aveugles à l'isolation par défaut, `CodingKey` imbriqués à
marquer `nonisolated`, `Bundle.module` devenant MainActor, https://fatbobman.com/en/posts/default-actor-isolation/).
On tranche : MainActor pour l'app seule ; si un kit accumule des `nonisolated`, c'est qu'il contient
de l'UI et doit être scindé.

**`@concurrent`** : seule annotation qui *garantit* l'exécution hors de l'acteur appelant (SE-0461,
https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md).
À poser sur les fonctions `nonisolated async` de calcul (pyramide, statistiques, ports Accelerate).

**Non-Sendable d'abord** (https://www.massicotte.org/blog/non-sendable-first-design/ ,
https://www.massicotte.org/mistakes-with-concurrency/) : un tampon image est une `final class`
non-Sendable transférée avec `sending`, jamais un `@unchecked Sendable`. « Les acteurs ne sont pas
des files » : rester sur le binaire main / pas-main ; un `actor` par état réellement partagé
(session Siril, cache de textures), pas un par module.

## 2. Architecture modulaire SwiftPM

- **`package` plutôt que `@testable`** : l'équipe Swift « décourage l'usage de `@testable` (bugs
  non maintenus, dépréciation prévue) » ; `package` permet de tester en build optimisé. Ne pas
  utiliser `package` *uniquement* pour tester : l'API d'un kit vers ses frères et ses tests est
  `package`, `public` seulement pour ce que l'app consomme.
  https://forums.swift.org/t/packge-import-or-internal-testable-import/74526
- **Frontières d'import** : `internal import Metal` (SE-0409) dans RenderKit empêche un type Metal
  de fuir dans une signature publique ; activer `InternalImportsByDefault`. Seul le graphe
  `dependencies` de `Package.swift` est contraint par l'outil : le test « module boundary » de 0040
  reste nécessaire (https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md).
- **Warnings = erreurs** : `.treatAllWarnings(as: .error)` + `.treatWarning("DeprecatedDeclaration",
  as: .warning)` (SE-0480, https://forums.swift.org/t/se-0480-warning-control-settings-for-swiftpm/79475).
  Ne touche pas les dépendances.
- **Strict memory safety** (SE-0458) : avertissements seulement, à activer dans ProjectKit,
  ProcessKit, HelpKit (peu de pointeurs) ; pas dans ImageKit/RenderKit où Accelerate et Metal
  noieraient le code sous `unsafe`. https://github.com/swiftlang/swift-evolution/blob/main/proposals/0458-strict-memory-safety.md
- **Migrer une feature plus tard** : `swift package migrate --to-feature …` (SE-0486).

## 3. Erreurs

- `throws` non typé reste le défaut des API publiques des kits ; SE-0413 : « untyped throws is
  better for most scenarios », typer « parce qu'une implémentation ne lève qu'un type » freine
  l'évolution. https://github.com/apple/swift-evolution/blob/main/proposals/0413-typed-throws.md
- `throws(SirilOutputError)` **à l'intérieur** d'un module quand l'appelant fait un `switch`
  exhaustif (parse de la sortie Siril, verdicts de sélection de trames).
- `Result` pour stocker/transmettre un résultat, jamais comme convention de retour.

## 4. Injection de dépendances et testabilité

- **Client = struct de closures** (Point-Free, *Designing dependencies*) : `struct SirilRunner {
  var run: (SirilScript) async throws -> SirilOutput }`, passé explicitement par l'init. La variante
  de test rejoue les sorties enregistrées par 0044. Aucune bibliothèque requise.
  https://github.com/pointfreeco/swift-dependencies (doc *DesigningDependencies*)
- **Metal « humble object »** : la logique (bornes, mise à l'échelle des paramètres `px`, layout des
  tampons) vit en Swift pur et se teste sans GPU ; RenderKit n'est qu'un encodeur mince. Sur un
  runner virtualisé `MTLCreateSystemDefaultDevice()` peut être `nil` ou un « Apple Paravirtual
  device » : les tests GPU **sautent** proprement (§8). https://github.com/actions/runner-images/issues/9254

## 5. Metal

- **Metal 3 maintenant.** Metal 4 (macOS 26, Apple silicon seulement, `MTL4*`, ressources non
  suivies, tables d'arguments) vise les moteurs de jeu ; adoption incrémentale supportée par Apple,
  `MTKView` expose déjà `currentMTL4RenderPassDescriptor`. Aucune app de traitement d'image en
  production trouvée sur Metal 4 : **à vérifier** plus tard, pas une base.
  https://developer.apple.com/documentation/metal/understanding-the-metal-4-core-api
- **Compilation des shaders — limite vérifiée** : les `.metal` déclarés en `resources:` ne sont
  compilés en `default.metallib` que par Xcode/`xcodebuild` ; `swift build` copie la source et
  `makeDefaultLibrary(bundle:)` échoue (https://github.com/swiftlang/swift-package-manager/issues/7716).
  Donc : chemin « runtime » `makeLibrary(source:)` pour `swift build`/CI, chemin précompilé quand
  Xcode est là, **mêmes options de compilation** sur les deux (test `testRuntimeAndPrecompiledAgree`
  de 0042). Alternative si la double voie pèse : `schwa/MetalCompilerPlugin`.
- **Metal Toolchain** = composant séparé dans Xcode 26 : `xcodebuild -downloadComponent
  metalToolchain` ; sans lui, un build `.metal` pend. `just doctor` le vérifie.
  https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components
- **Fast-math désactivé** pour tout noyau pinné par un oracle : `MTLCompileOptions.mathMode =
  .safe`, `mathFloatingPointFunctions = .precise` ; `MTL_FAST_MATH=NO` côté build. Réductions en
  ordre fixe, pas d'atomiques. https://developer.apple.com/documentation/metal/mtlcompileoptions/mathmode
- **MPS** (non déprécié) pour les opérateurs standard **non pinnés** (flou gaussien, min/max
  morphologique, histogramme) ; noyau maison pour tout ce qui porte R2 ou une parité (l'implémentation
  MPS varie selon la famille de GPU). https://developer.apple.com/documentation/metalperformanceshaders
- **Organisation** : un `.metal` par process + un `ShaderTypes.h` partagé (cible C) pour que la
  struct de paramètres soit unique Swift/MSL — « valeurs appliquées = valeurs montrées ».
- **Mémoire** : Apple silicon = mémoire unifiée ; `.shared` pour les plans remplis par le CPU
  (`makeBuffer(bytesNoCopy:)` page-aligné, zéro copie avec vImage), `.private` pour les
  intermédiaires GPU, vues `r32Float` seulement là où l'on échantillonne.
  https://developer.apple.com/documentation/metal/choosing-a-resource-storage-mode-for-apple-gpus
- **Diagnostic** : Shader Validation (`MTL_SHADER_VALIDATION=1`) dans les tests GPU locaux ;
  capture programmée `MTLCaptureManager` vers `.gpuTraceDocument` pour les tests de budget.

## 6. Accelerate

- API typée `vImage.PixelBuffer<vImage.PlanarF>` (macOS 13+) sur la même mémoire que `vDSP` ;
  `InterleavedFx3` seulement en sortie TIFF/PNG. https://developer.apple.com/documentation/accelerate/creating-vimage-pixel-buffers
- **Déterminisme** : reproductible sur une puce pour une séquence d'appels fixe ; **pas garanti
  entre puces** (ordre de sommation vectorisée ; cas MLX M1 vs M3/M5). D'où : bits exacts
  **seulement** sur ce que Siril produit (scripts, masters) ; tolérances partout ailleurs.
- `Span`/`InlineArray` (SE-0447/0453, macOS 26) pour les boucles chaudes d'ImageKit, sinon
  `UnsafeMutableBufferPointer` derrière `unsafe`. https://developer.apple.com/videos/play/wwdc2025/312/

## 7. Document, persistance, processus externes, localisation

- **Document** : Apple DTS recommande désormais `FileDocument` (struct) + modèle `@Observable`
  séparé, parce que `ReferenceFileDocument` hérite d'`ObservableObject`
  (https://developer.apple.com/forums/thread/785500). Mais un paquet `.astrostack` contient un
  SQLite et des FITS de 22 Mpx : le « safe-save » de `FileWrapper` remplace le paquet, ce qui
  oblige à copier la base à chaque snapshot (https://www.hackingwithswift.com/forums/swiftui/documentgroup-filedocument/17157).
  **Recommandation 0040/0068** : `NSDocument` (via `NSApplicationDelegateAdaptor`, contenu SwiftUI)
  avec `writeSafely(to:ofType:for:)` surchargé pour laisser la base et les images en place et ne
  checkpointer que la DB. **À vérifier** sur le prototype : aucune mesure publiée de `FileWrapper`
  au-delà de quelques centaines de Mo.
- **SQLite = GRDB 7** (7.11, Swift 6.1+, zéro erreur de data-race sur SPI) : `DatabasePool` par
  document ouvert, `DatabaseMigrator` (une migration = un fichier, jamais éditée après merge,
  `eraseDatabaseOnSchemaChange` en DEBUG seulement), `ValueObservation` pour l'UI ; `created_at`/
  `updated_at` en ms int64 (convention maison). SQLiteData (Point-Free) écarté : base globale
  unique, 16 dépendances. https://swiftpackageindex.com/groue/GRDB.swift
- **Processus externes = swift-subprocess 1.0** (Swift 6.2+, structured concurrency) :
  `Subprocess.run(.path(...), input: .fileDescriptor(fd, closeAfterSpawningProcess:), output:
  .sequence)` ; annulation → `PlatformOptions.teardownSequence` (SIGTERM puis SIGKILL) ; **pas de
  timeout intégré** → `withThrowingTaskGroup` + `Task.sleep`. Les FIFO Siril s'ouvrent avec
  `FileDescriptor.open` et se passent tels quels. `Foundation.Process` écarté (non Sendable,
  exceptions ObjC). https://github.com/swiftlang/swift-subprocess
- **Localisation** : un `Localizable.xcstrings` par cible, `defaultLocalization: "en"`,
  `bundle: #bundle`. Bug Xcode 26.4 : les symboles générés du catalogue ne compilent pas sous
  `defaultIsolation(MainActor.self)` → ne pas dépendre des symboles générés dans l'app.
  https://developer.apple.com/forums/thread/824485 . Aide = Markdown en ressources, rendu par
  `swift-markdown-ui` (GFM) ; `AttributedString(markdown:)` ne fait que l'inline.
- **Observabilité** : un `Logger(subsystem: "fr.astrostack", category: "<kit>/<sujet>")` par
  sujet ; valeurs interpolées privées par défaut, `privacy: .public` explicite ; `OSSignposter`
  sur le même logger autour de chaque passe GPU et de chaque étape Siril (Instruments 26 montre
  cause → effet SwiftUI). https://developer.apple.com/documentation/os/ossignposter

## 8. Tests : ce que l'on écrit, et comment

**Swift Testing (6.3) — idiomes retenus**

- **Suites live** : nom préfixé `Live` + trait de condition ; elles apparaissent *skipped*, jamais
  vertes par défaut :
  ```swift
  extension Trait where Self == ConditionTrait {
    static var liveFixtures: Self {
      .enabled(if: LiveFixtures.root != nil, "~/Documents/astro/fixtures absent")
    }
  }
  @Suite(.liveFixtures, .tags(.live), .serialized) struct LiveSirilOracleTests { … }
  ```
  Le filtrage par tag en CLI (`--filter tag:live`) n'arrive qu'avec Swift 6.4 (ST-0025) ; d'ici
  là `swift test --skip Live` donne la boucle rapide, et le trait reste la vraie garde.
  https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Testing.docc/Traits.md
- `.serialized` sur tout ce qui touche Siril ou un scratch partagé (Swift Testing est parallèle par
  défaut) ; `.timeLimit(.minutes(n))` (minutes seulement) sur les suites live.
- **Tolérances** : Swift Testing n'a pas d'`accuracy:` ; un helper `ImageDiff` renvoie
  `meanAbs`, `maxAbs`, `psnr` et le test affirme les trois avec les seuils écrits en clair ; en
  échec, `Attachment.record(diffImage, named:, as: .png)` (ST-0014, Xcode 26.4) et CI remonte
  `--attachments-path`.
- **Oracles hors dépôt** : manifeste committé (chemin, sha256, tolérance, versions des outils) ;
  le test vérifie le hash du golden avant de comparer, pour qu'un golden périmé échoue fort ;
  `RECORD=1` réenregistre.
- **Snapshots texte** (`swift-snapshot-testing`, trait `.snapshots(record:)`) pour les scripts
  `.ssf`, les plans JSON, les aperçus 8 bits ; jamais pour du float32.
- **Exit tests** (`#expect(processExitsWith:)`) pour pinner les `precondition` d'invariants R2.
- **Benchmarks** : `ordo-one/package-benchmark` avec seuils relatifs ≥ 20–30 % en CI (M1 partagé),
  seuils serrés et budget 16 ms **en local seulement** (`just bench`). Muter (mutation testing)
  n'a pas de support Swift 6 / Swift Testing documenté : écarté.

**Déterminisme GPU en CI** : le runner expose un « Apple Paravirtual device » (compute OK, familles
sous-déclarées, timings instables). Les tests de noyaux tournent en CI **avec tolérance** et sautent
si le device est `nil` ; parité serrée et budgets de frame = local.
https://github.com/JuliaGPU/Metal.jl/pull/789

## 9. Portes qualité et CI

| Porte | Outil | Où |
|---|---|---|
| Format + règles syntaxiques | `swift format lint --strict` (bundled, config `apps/macos/.swift-format`) | `just lint`, CI |
| Métriques de maintenabilité (taille fichier/type/fonction, complexité, force-unwrap, `print`, `DispatchQueue`, `CIImage`) | SwiftLint 0.65 (`apps/macos/.swiftlint.yml`, règles custom = règles CLAUDE.md) | `just lint`, CI |
| Warnings | `.treatAllWarnings(as: .error)` par cible | build |
| Hygiène dépôt (pas de Go/Python/Docker/pixels/symlinks) | `scripts/hygiene.sh` (préfigure le test de 0064) | `just hygiene`, CI |
| Tests unitaires + oracles committés | `swift test` | `just test`, CI |
| Tests live (outils hôte + fixtures) | mêmes suites, préfixe `Live`, auto-skip | `just check` local avant PR |
| Couverture | `swift test --enable-code-coverage` + `llvm-cov` | `just coverage` ; **seuil fixe 95 %** (`.coverage-floor`), décision PO du 24/10 (remplace le ratchet) ; seul le PO le change |
| API publique des kits | `swift package diagnose-api-breaking-changes origin/main` | à ajouter en CI dès qu'un kit est `public` (0049) |
| Code mort | Periphery 3.7.4 (dernière version MIT ; projet passé commercial 08/2026) | nightly local, pas en PR |
| Pré-push | `scripts/git-hooks/pre-push` → `just check` (installé par `just hooks`) | local |

**CI hébergée (`.github/workflows/tests.yml`)** : `runs-on: macos-26` (image = macOS 26.6, Xcode 26.6
par défaut + 26.0–26.5 ; `macos-15` reste sur Xcode 16.4 par défaut), Xcode sélectionné
explicitement, cache `.build` sur `Package.resolved`, étape gardée `xcrun metal --version ||
xcodebuild -downloadComponent metalToolchain` (présence du Metal Toolchain sur l'image
**contestée** entre runner-images #13080 et #13014), `timeout-minutes: 30`, `concurrency` avec
annulation. https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md

**Coût** : minutes macOS facturées **×10** ; un dépôt privé sur GitHub Free dispose de 2 000
minutes/mois, soit **~200 minutes macOS**, ~20–30 runs. D'où : CI **sur `pull_request` seulement**
(le squash-merge d'une PR verte vaut main), cache, annulation des runs obsolètes. Si cela coince :
un **runner self-hosted sur le Mac du PO** (vrai GPU, Siril, GraXpert, fixtures présents — la
suite live devient CI-able) ; dépôt privé mono-développeur, risque acceptable.
https://docs.github.com/en/billing/reference/actions-runner-pricing

**Protection de branche** : indisponible sur un dépôt privé Free (API 403 vérifiée le 20/10). Le
skill pick-card attend donc la fin des checks (`gh pr checks --watch` puis vérification) avant
`gh pr merge --squash`, jamais `--auto`. Passer le dépôt en public ou en Pro débloque les rulesets
(PR obligatoire, checks requis, historique linéaire).

## 10. Où chaque règle s'applique (par carte)

- **0040** : `Package.swift` avec les `swiftSettings` du §1, `.swift-format` et `.swiftlint.yml`
  (préparés), `just` réel, CI réelle, test « module boundary », `NSDocument` + GRDB décidés ici.
- **0041** ImageKit : `vImage.PixelBuffer`, `@concurrent` sur la pyramide, `Span` si macOS 26
  plancher, lecteur FITS pinné par checksums Go.
- **0042** RenderKit : Metal 3, fast-math off, double voie runtime/précompilée testée, tests GPU
  avec tolérance et skip, budget 16 ms local-only, `MTKView` en mode `enableSetNeedsDisplay`.
- **0044 / 0067** oracles : manifeste + hash + `RECORD=1`, suites `Live…`, trait `liveFixtures`.
- **0045** Siril : swift-subprocess, FIFO ouvertes par nous, timeout par task group, struct-de-
  closures `SirilRunner` rejouée en test, `.serialized`.
- **0046–0048, 0066** ports : `throws(…)` typés internes, tests Go traduits en `@Test(arguments:)`,
  tolérance 1e-5 rel pour Accelerate, bits exacts seulement sur scripts/masters.
- **0049** ProcessKit : contrats `PreviewEqualsApply`/`NoHiddenState`/`PxUnitsScale`, `ShaderTypes.h`
  unique, `diagnose-api-breaking-changes` activé en CI dès la première API `public`.
- **0068** ProjectKit : migrations SQL up/down (`Migrator` maison, `DatabaseMigrator` sans down), immuables, ms int64, strict memory safety.
- **0061** HelpKit : `.xcstrings` par cible, `#bundle`, Markdown GFM, porte de couverture fr/en.
- **0064** : le test `RepoHygieneTests` reprend `scripts/hygiene.sh` en Swift.
- **0065** : Metal Toolchain en CI, signature — réévaluer runner self-hosted vs hébergé.

## 11. Non vérifié (à confirmer quand la carte arrive)

- Comportement de `swift build` sur les `.metal` sous le nouveau « Swift Build » (6.4).
- Maturité de Metal 4 pour un pipeline compute image.
- Déterminisme bit-exact de vDSP entre puces (indices contraires, pas de déclaration Apple).
- Tenue de `FileWrapper` au-delà de quelques centaines de Mo (aucune mesure publiée).
- Présence du Metal Toolchain et de swiftlint sur l'image `macos-26` (le workflow se protège).
- Réglage par défaut d'Approachable Concurrency dans les nouveaux projets Xcode 26 (on le fixe
  explicitement dans `Package.swift`, on ne s'y fie pas).
