# Roadmap

## Ideas for features

* `prune.references: strip` rather than `remove`.
* `via`: Parse relationships from A to B to C as relationships from A to C. E.g.
  
	```yaml
	from: projects
	to: services
	via: self, deliverables
	```
* Multiple output frontmatter locations

