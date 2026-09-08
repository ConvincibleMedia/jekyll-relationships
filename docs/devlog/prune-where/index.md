# Frontmatter-based tree pruning

Add tree-pruning selection by exact frontmatter values while preserving the existing pruning pipeline and tree guarantees.

Status: verification pending

Current stage: verification

## Scope

* Accept a non-empty `where` hash on tree prune rules.
* Permit tree rules containing `where`, complete `min`/`depth` settings, or both.
* Match document frontmatter by hash-only dot paths with exact, type-sensitive equality and a distinction between missing and present `null` values.
* Combine `where` and relationship-count selection with AND semantics.
* Contract consecutive removed tree nodes to the nearest surviving ancestor on each original parent lineage when the configured orphan policy reconnects grandparents.
* Preserve existing orphan policies, graph ordering, limits, cycle protection, provenance and final collection removal.
* Add configuration and integration coverage.

## Stages

* Implementation: complete
* Verification and completion: pending test execution

## Key decisions and findings

* `where` is supported only by tree prune rules; normal relationship pruning remains unchanged.
* Dot paths traverse hashes only. Arrays and hashes can be exact terminal values.
* Type-sensitive equality requires matching Ruby classes as well as equal values.
* Each original parent lineage stops at its first surviving ancestor; candidates are deduplicated in original traversal order.
* Existing orphan policies remain authoritative when no ancestor survives.
* The existing orphan repair only searches one generation and therefore requires transitive provenance traversal for consecutive removals.
* Project coding guidance prohibits running tests or builds without an explicit request; Ruby syntax verification is complete, but behavioural suite execution remains pending.
