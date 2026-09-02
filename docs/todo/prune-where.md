# J-R requirement: frontmatter-based tree pruning

Status: implemented; test-suite verification tracked in the development log.

## Objective

Allow tree relationships to prune documents selected by frontmatter values, using the existing tree orphan-repair and pruning pipeline.

Example:

```yaml
- from: pages
  to: self
  mode: parent
  prune:
    where:
      exists: false
```

This removes pages with `exists: false` frontmatter, while promoting their children to the nearest surviving ancestors.

## Tree pruning modes

A tree `prune` block supports two modes:

1. Relationship mode: `min` and `depth`, which must be specified together.
2. Frontmatter mode: `where`.

A tree prune block must define at least one complete mode. It may define both.

Invalid configurations include:

```yaml
prune:
  min: 1
```

```yaml
prune:
  depth: -1
```

```yaml
prune:
  where: {}
```

The first example is invalid because `depth` is missing; the second is invalid because `min` is missing. Negative depths remain valid when the relationship mode is complete.

Normal-relationship pruning behaviour is unchanged.

## `where` behaviour

`where` is a hash of frontmatter paths to expected values:

```yaml
prune:
  where:
    exists: false
    meta.status: hidden
```

Requirements:

* Paths are relative to document frontmatter.
* Dot notation traverses nested hashes only. Arrays and hashes can be matched as complete terminal values.
* Matching is exact and type-sensitive: both the Ruby type and value must be equal.
* A present `null` matches an expected `null`; a missing field does not match any value.
* Multiple entries are combined with AND.
* `where` applies to the pruning subject:
  * The `from` collection normally.
  * The inverse subject when `prune.mode: inverse`.
* A document matching a `where`-only rule is pruned unconditionally.
* When `where` and `min`/`depth` are combined, both modes must select the document.

## Graph processing

J-R must:

1. Construct the complete source graph before applying `where` pruning.
2. Resolve references, collections and scopes normally.
3. Pass matching documents into the existing pruning/removal pipeline.
4. Traverse original tree provenance to reconnect surviving children to the nearest surviving ancestor on each parent lineage when the configured orphan mode requests reconnection.
5. Support chains of multiple consecutively pruned nodes.
6. Follow the configured orphan policy when no surviving ancestor exists: retain a graph root for `grandparents` or `orphan`, and remove it for `grandparents required` or `prune`.
7. Preserve existing ordering, parent limits, cycle protection and relationship provenance.
8. Remove pruned documents from the active relationship set and final Jekyll collection as with existing pruning.
9. Leave document URLs and permalinks unchanged.

## Acceptance example

Given:

```text
Legal (exists: false) → Privacy Policy
```

J-R should produce:

```text
Privacy Policy
```

as a graph root, with Legal removed.
