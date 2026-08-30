# J-R requirement: frontmatter-based tree pruning

## Objective

Allow tree relationships to prune documents selected by frontmatter values, using the existing graph-contraction and pruning pipeline.

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

- Paths are relative to document frontmatter.
- Dot notation addresses nested fields.
- Matching is exact and type-sensitive.
- A missing field does not match `false` or any other value.
- Multiple entries are combined with AND.
- `where` applies to the pruning subject:
  - The `from` collection normally.
  - The inverse subject when `prune.mode: inverse`.
- A document matching a `where`-only rule is pruned unconditionally.
- When `where` and `min`/`depth` are combined, both modes must select the document.

## Graph processing

J-R must:

1. Construct the complete source graph before applying `where` pruning.
2. Resolve references, collections and scopes normally.
3. Pass matching documents into the existing pruning/removal pipeline.
4. Use the graph contractor to reconnect surviving children to their nearest surviving ancestors (when that is the configured mode).
5. Support chains of multiple consecutively pruned nodes.
6. Leave a child as a graph root when no surviving ancestor exists.
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