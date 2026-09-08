# Changelog

## 0.2.0.alpha

* Scopes: can now define a `scope` in which primary key references are to be evaluated, and the scope value can come implicitly from the referring document.
* Ensure forward relationships resolve before inverse ones which should be merely mirrors
* Tree pruning can now select documents by exact frontmatter values with `prune.where`, including combined `min`/`depth` selection and transitive orphan reconnection.

## 0.1.1.alpha

* Various major bug fixes.
* Added option to make links persist even if pruning removes the transitive relationship that added them, with `link(ref, persist: true)`.
* References in frontmatter at a non-output location will no longer be upgraded (modified).
* `depth` available for trees.

## 0.1.0.alpha

* Documents can specify relationships to each other using a primary key.
* Can specify both the frontmatter keys to read from, and also different output frontmatter keys.
* References to other documents are upgraded in the source frontmatter to include other details and a direct page link.
* First-class tree relationship parsing.
* URL mode: determine tree relationships by final path.
* Custom resolvers allow more complex and configurable relationship parsing.
* Options for how to handle multiple links to the same document.
* Document graph pruning: remove documents that link to/are linked to by fewer than a minimum.
