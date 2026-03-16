# Jekyll Relationships

Plugin for Jekyll that allows collection documents to specify their relationships with each other, via many-to-many links. These can form trees, graphs or relational-database-like structures. Exposes the relationships in each document's frontmatter.

## Configuration

How documents link to each other is specified by configuration.

```yaml
relationships:
  # The relationships that exist on this site
  relationships: # array, see Relationships below

  # The frontmatter keys that specify relationships - global defaults
  frontmatter: # see Frontmatter below
    base: relationships # prepend to other keys
    primary: nil # use Document path as primary key
    foreign: <collection> # because of base, treated as `relationships.<foreign>`
    output: nil # see Output below

  # Modify the shape of the foreign reference object
  references: # see References below
    id: <key>
    collection: <collection>
    page: <page>

  # Settings for tree relationships
  tree: # see Trees below
    frontmatter:
      parent: parent # which keys specify a single parent
      child: child # which keys specify a single child
      parents: parents # which keys specify multiple parents
      children: children # which keys specify multiple children
      ancestors: ancestors # key on which to set ancestors
      descendants: descendants # key on which to set descendants
    max:
      parents: -1 # max parents per item (-1 = unlimited)
      children: -1 # max children per item
    url: false # infer parent by item url

  # Override keywords in case they are a clash with your collection/frontmatter names
  keywords: # see Keywords below
```

The values shown above are the built-in defaults that will apply even if you don't specify these settings at all.

Throughout the config, any item which can be an array may also be given as a single string (implicitly a one-item array) or a comma-delimited string (will be split to an array).


## Relationships

`relationships` is an array specifying the relationships on this site. Example:

```yaml
relationships:
# categories and tags are each in a tree
- from: categories, tags
  to: self
  mode: parent
# products
- from: products
  to: categories, tags
  frontmatter: # override for this relationship
    base: data # override `base` for this `frontmatter`
    foreign: <collection>, links # find references at `data.categories`, `data.tags` and `data.links`.
- from: products
  to: # array form
  - collection: products # hash form
    frontmatter: # override frontmatter for this `to` target
      foreign: body.subproducts
  - services # regular string form
  - collection: product-types
    mode: tree # override `mode` for this `to` target
  mode: bidirectional
```

Each array item has:

* `from` (required): one or more collection labels.
* `to` (rquired): one or more collection labels.
  * Each item in `from` is related to each item in `to`.
  * Instead of a collection label a keyword can be used:
    * `self`: each item in `from` relates "to itself". E.g. if an item in `from` is `products` then `self` means `products` for that item i.e. products can relate to other products.
    * `others`: each item in `from` relates to any of the other items besides itself
    * `all`: each item in `from` relates to any of those items including itself
  * Instead of a string a hash can be used:
    * `collection`: the string as before
    * Hash can also specify a local `frontmatter` and/or `mode` override
* `frontmatter` (optional): the values set in global config apply to all relationships by default, but you can override specific properties of it per relationship by setting them here.
* `mode`
  * `link` (default): `from` links to `to`.
  * `parent`/`child`: items in `from` can have items in `to` as their parent/child (which also implies the reverse relationship). See [Trees](#trees) below.
  * `bidirectional`: like `link`, but whenever a link is added, it is also added to the target in the reverse direction automatically.

Duplicate or clashing relationship definitions will throw an error. A bidirectional relationship "uses up" the reverse definition, so "from A to B, bidirectional" followed by a "from B to A, link/bidirectional" definition is a duplicate and throws an error.

The defined relationships will be processed and resolved. This will:

* Ensure arrays of references are complete
* Upgrade the references between documents to richer objects
* Protect against invalid or duplicate references (A can't link to B twice in the same array)


## Frontmatter

Relationships between documents are specified by values in each document's frontmatter. Somewhere in the frontmatter of documents you must have:

* A "Primary Key": a value that identifies this document
* A "Foreign Key": a value that identifies another document's primary key

You specify where in the frontmatter these primary/foreign keys exist, using:

```yaml
frontmatter:
  primary: id # the frontmatter key `id` holds the primary key value
  foreign: <collection> # <collection> is replaced by the label of a `to` collection. The frontmatter key that matches this label holds a reference to a document in that collection.
```

* Both keys can be specified with dot-notation to access deeply nested keys, e.g. `meta.details.relationships.id`.
* `<collection>` is valid only within `foreign`. Example:
  
  ```yaml
  relationships:
  - from: products
    to: categories, tags
    frontmatter:
      foreign: links.<collection>_links
  ```

  In `products` documents, this would find links to `categories` at `links.categories_links` and links to `tags` at `links.tags_links`.
* `foreign` can be an array of frontmatter locations where references will be read. These will all be accumulated.

### Output

Relationships are read from the keys you give, and processed. Processing may modify the relationships, add/removing some. This will be written back into the frontmatter at the first location defined in `foreign`. However, if you want to leave this alone, a separate key `output` gives the frontmatter location where you want the final set of relationships to be written. It may contain `<collection>`. Example:

```yaml
relationships:
  frontmatter:
    base: ''
    primary: meta.id
    foreign: data.<collection>
    output: meta.relationships.<collection>
```

### Base

Any definition of `frontmatter` may specify a `base` which will be prepended to both the `primary` and `foreign` keys within that `frontmatter` definition.

```yaml
frontmatter:
  base: links
  primary: id # treated as `links.id`
  foreign: <collection> # treated as `links.<collection>`
```

The default `base` is `relationships` i.e. all information about relationships is by default read from and stored under a `relationships` key on any document in the site.

You can unset `base` with an empty string.

### Defaults and Overrides

`frontmatter` settings for any given relationship is determined by a series of overrides:

1. Built-in defaults
2. Global config
3. Override at relationship level
4. Override at `to` level

For instance if `base` is defined higher in the chain, it will apply by default to any `frontmatter` given lower down, unless it is unset at that level.


## References

In a document's frontmatter, a link from one document to another is a "reference". The references in frontmatter can be either:

* A string of the foreign key
* A reference hash where some property gives the foreign key
* An array of either of the above, or mixing the above.

Example:

```yaml
# superbrand-shoes.md
title: SuperBrand Shoes
relationships:
  categories:
  - Shoes
  - id: Trainers
  - Clothing
```

The `references` config lets you modify the shape of reference hashes. Its keys are arbitrary, and its values can be:

* `<key>` exactly (required): this key gives the foreign key, and must be present.
* `<collection>`: this key gives the collection in which the foreign document exists.
* `<page>`: this key will be set to the actual `Jekyll::Document` instance for the foreign document.

Example:

```yaml
# _config.yml
relationships:
  references:
    link_to: <key> # foreign key is now stored on the property 'link_to'
    # collection is removed
    page: <page>
```

When relationships are processed, references are read loosely: strings are foreign keys, hashes look at the foreign key/collection keys only, ignoring others. Following resolution, all references are upgraded to the defined hash form (merging over any other keys on an existing hash).


## Primary Keys

**Primary keys must be unique** within a collection. However, if you set things up so that primary keys are unique across *all* collections, then you no longer need to know the collection of a document when linking to it: just the foreign key is needed.

If the collection isn't given by the reference, all collections will be searched to find the foreign key. If non-unique keys are found this will raise an error.

When the `primary` config is `nil`, (which is the default), the document "path" is used as the primary key. This guarantees uniqueness across the whole site. Document path is `Document#relative_path` with leading `_` and trailing `Document.extname` removed, giving strings like `products/shoes` for `shoes.md` in the `products` collection.


## Trees

In Tree mode, documents can be the parents or children of other documents. This type of relationship has special handling and helpers.

Tree mode is activated on a relationship with `mode` set to:
* `parent`: `to` items can be parents of `from` items
* `child`: `to` items can be children of `from` items
* `parent/child` or `child/parent`: both `to` and `from` items can be parents of each other

Note that the `parent`/`child` relationship is symmetric. If A is a parent of B, then B is a child of A. As soon as one is set one way, the other is implied.

Tree mode can be configured under `tree`:

* `frontmatter`: set the keys that will be used for single/multiple parents/children and ancestors/descendants.
* `max`: set max allowed parents/children (default `-1` i.e. unlimited).
* `url`: interpret URLs as ancestry information (default false).

Tree relationships must be declared in `relationships.relationships` with `mode: `. `from`, `to` and whether mode is `parent` or `child` define the relationship's directionality. Swapping `from`/`to` and `mode` would define the same thing.

Tree relationships are processed as follows:

* Only for declared relationships, look for parents/children in valid directions on documents:
  * By inspecting:
    * The `#url`s of the documents, if config `url: true`. See [URL mode](#url-mode) below.
    * References found in the frontmatter keys on the item (by default, `relationships.parent(s)` and `relationships.child(ren)`).
      * In each case, the value can be a reference directly, or an array of references.
  * All parents/children specified by either method, and by any relationship, are accumulated.
  * This happens across all items, in an initial pass, building a complete graph.
  * Documents can choose whether to specify parents, children, both, or neither. The graph will be built up using the information given in either direction. E.g. if A can be a parent of B, then it will look for B-children of A, and A-parents of B.
  * Protections against loops (including the 0-length case of self-reference) are built-in. If an ancestor/descendant chain attempts to make a link that forms a loop, the chain is broken before adding that link and the attempted link is deleted. A warning is issued but processing otherwise continues.
* Having built the graph, the tree links are filled in on each document:
  * `parents` and `children` are set as arrays of the immediate ancestors/descendants as reference hashes.
  * `ancestors` and `descendants` are set as arrays where each element is a reference hash. In this situation the hash gains the property `distance`, which is 0 for self, 1 for immediate parent/child, 2 for grandparent/grandchild, etc. The arrays are in ascending distance order. If an item can be reached by multiple paths, the shortest path gives the distance.

### Max

The `max` config lets you specify a maximum number of allowed parents/children in a relationship.

If more than the max number of parents/children are encountered, only the first up to max are used, and all other attempts to add parent/child fail and that reference is deleted. A warning is issued but processing otherwise continues.

For each of `max.parents`/`max.children`, if the value is `1`, the singular `parent`/`child` keys will be used to read the parents/children (otherwise all keys are used) and to set the `parent`/`child` values (which will be the reference directly, not in an array).

### URL mode

In URL mode the `url` property of documents are inspected to find parent relationships. On each document, URLs are normalised (no leading/trailing slash, `index.html` removed) and split on `/`, to give a set of URL parts. To find tree relationships in the target collection:

* A parent has the same URL parts minus the last one
* A child has the same URL parts plus one more part.


## Resolvers

You can insert special logic that modifies how the links from X to Y are resolved, by defining and registering one or more Resolver classes for a relationship.

Resolvers run for normal relationships (`link` or `bidirectional`), not Tree relationships.

Resolvers must be placed in `Jekyll::Plugins::Relationships::Resolvers` and inherit from `Jekyll::Plugins::Relationships::Resolvers::Base`. They could be defined by files in your `_plugins` folder, for instance.

Each Resolver must specify the relationship it applies to with the `from` and `to` directives. These have the same syntax and interpretation as `from` and `to` in a relationship definition. The Resolver will run for any implied pair of collections.

```ruby
class ProductsAndCategories < Jekyll::Plugins::Relationships::Resolvers::Base
  from 'products, categories'
  to 'self'

  # Called for each item in the collection
  def resolve
    # use link(reference) and unlink(reference) to modify links on this document from `from` to `to`
  end

end
```

The Resolver class is instantiated each time that type of relationship is being resolved for some document. The `resolve` method is called, and this has a chance to modify that document, and the documents it links to.

The instance has these variables already set:

* `@key`: primary key of the document currently being resolved
* `@from`: label of the collection this item belongs to
* `@to`: label of the target collection, links to which are currently being resolved
* `@site`: the `Jekyll::Site`

This document's links are modified with the `link` and `unlink` methods:

* `link(reference)`
  * `reference` gives the document to link to, from this document. It must be in the `@to` collection.
  * `reference:` (optional named parameter): gives a hash that the created reference hash will merge over, providing arbitrary addititional properties to the hash.
  * Adding a duplicate link has no effect.
* `unlink(reference)`
  * Remove the link to the `reference`d document.
  * `unlink` (no reference) removes all links on this document to the `@to` collection.

Because the class extends `Resolvers::Base` it has access to these helpers:

* `relationships(reference, to: collection)`
  * Gets an array of reference hashes for the relationships from the `reference`d document to the collection passed as `to`.
    * This causes the requested relationships to be resolved immediately on that foreign document, creating a recursion. Cyclic dependencies are detected and throw an error.
  * If `to` is omitted, the value of `@to` is used.
  * You can get those relationships on *this* document to the target collection: this will return current links. You can modify from there.
* Tree-traversal methods:
  * `parents(reference)`: shorthand for `ancestors(reference, max: 1)`.
  * `ancestors(reference)`
    * Returns the array of ancestors of the `reference`d document, where each array item is a reference hash with `distance`.
    * `max` (optional, default `-1`): the max `distance` to search/return. `-1` means no limit.
    * `min` (optional, default `1`): the min `distance` to search/return. `0` would include the item itself.
  * `children(reference)`: shorthand for `descendants(reference, max: 1)`.
  * `descendants(reference)`: equivalent to `ancestors` but looking in the opposite direction.
* `document(reference)`: retrieves the `reference`d document.
  * Only valid for items participating in relationships.
  * If that document itself has defined relationships, it recurses to resolve those first, unless that document is this document.
  * Returns the actual `Jekyll::Document`.

The `reference` parameter in all the above:

* Can be a reference (i.e. a key string or reference hash). If optional `from` is passed, or the reference hash has collection info, the key lookup is constrained to that collection.
* Can be a `Jekyll::Document` object. Its primary key and collection are read from the object.
* Can be omitted in the helpers, in which case the method operates on *this* document.

### Example

```ruby
class ProjectServices < Jekyll::Plugins::Relationships::Resolvers::Base
  from 'projects'
  to 'services'

  # Services on this project are determined by looking at
  # its deliverables and all of their ancestors
  # and the services they link to
  def resolve
    relationships(to: 'deliverables').each do |deliverable|
      ancestors(deliverable, min: 0).each do |ancestor|
        relationships(ancestor, to: 'services').each do |service|
          link(service, reference: { distance: distance(ancestor) + distance(service) })
        end
      end
    end
  end

  # Helper to add distance info to added links
  def distance(reference)
    if reference.has_key?('distance')
      reference['distance']
    else
      0
    end
  end

end
```


## Recursive Resolution

Relationships are resolved recursively, while also guaranteeing that each relationship and document is resolved exactly once. E.g. if in order to resolve X we need the final state of Y, we recurse into Y and resolve it first.


## Keywords

In many places, certain keyword strings have special meaning. In case these strings clash with a collection name or frontmatter key, you can change them with the `keywords` config.

```yaml
keywords:
  base: prepend
  self: itself
  #etc for all reserved tokens that can be used in a context where collection names or frontmatter keys can also be given
```


## Examples

```yml
# Portfolio site
relationships:
  frontmatter:
    base: ''
    primary: meta.id
    foreign: data.<collection>

  relationships:
  # Clients have an organisation type, industry and location
  - from: clients
    to: org_types, industries, locations
  # Deliverables, industries and locations can nest inside themselves
  - from: deliverables, industries, locations
    to: self
    mode: parent
  - from: deliverables
    to: services
  - from: projects
    to:
    - services
    - collection: deliverables
      frontmatter:
        foreign: data.deliverables, data.body.details.deliverables
    - collection: clients
      frontmatter:
        foreign: data.client
```