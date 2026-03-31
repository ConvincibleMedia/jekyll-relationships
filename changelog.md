# Changelog

## 0.1.1.alpha

* Various major bug fixes.
* Added option to make links persist even if pruning removes the transitive relationship that added them, with `link(ref, persist: true)`.
* References in frontmatter at a non-output location will no longer be upgraded (modified).

## 0.1.0.alpha

* Documents can specify relationships to each other using a primary key.
* Can specify both the frontmatter keys to read from, and also different output frontmatter keys.
* References to other documents are upgraded in the source frontmatter to include other details and a direct page link.
* First-class tree relationship parsing.
* URL mode: determine tree relationships by final path.
* Custom resolvers allow more complex and configurable relationship parsing.
* Options for how to handle multiple links to the same document.
* Document graph pruning: remove documents that link to/are linked to by fewer than a minimum.