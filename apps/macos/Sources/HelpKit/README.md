# HelpKit

Help content: process cards, "why this value", the first-stack guide, in French and English
(design §6).

**State:** empty module (card 0040). Cards 0049 (coverage gate) and 0061 (content) fill it.

**How to extend:** Markdown in resources, one `Localizable.xcstrings`, resolved with
`bundle: #bundle`; a process without a fr+en card fails the coverage gate. Allowed dependencies:
none (`Tests/TestSupport/BoundaryRules.swift`).
