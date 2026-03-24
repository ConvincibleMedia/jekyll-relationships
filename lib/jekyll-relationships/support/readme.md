# Helpers

## FrontmatterPath

Use `Jekyll::Plugins::Support::FrontmatterPath` to traverse nested frontmatter with:

* configurable separator
* array traversal (`:expand` or `:first`)
* equivalent-key lookup

Example:

```ruby
path = Jekyll::Plugins::Support::FrontmatterPath.new(
	separator: '.', # nested keys accessed with e.g. product.subcategory.name
	arrays: :expand,
	equivalents: [
		# seeking one of these key-sets will also find and merge together the others: they are treated as if all in the set are the same key
		%w[tag tags],
		['product.tag', 'product.tags']
	]
)

path.traverse(data, 'product.tag')
```

`traverse` returns:

* `nil` when the path is missing.
* if arrays are encountered at a mid-point in the path:
  * `:expand` mode (default): values are accumulated across the array and traversal continues for each, ultimately returning an accumulated array. Example:

	```yaml
	product:
		categories:
		- name: boots
		- name: shoes
	```

	`product.categories.name` returns `['boots', 'shoes']`.
  * `:first` mode: the first array item is used and traversal continues

Use `with(...)` to derive a nearby variant without restating the full config:

```ruby
template_path = path.with(separator: ':')
```


## StringArray

Use `Jekyll::Plugins::Support::StringArray` to interpret values as arrays. If the value is an array it just returns it. Depending on configuration, if values are strings, they may be split to arrays.

Example:

```ruby
@array_comma = Jekyll::Plugins::Support::StringArray.new(delimiter: ',')

@array_comma.interpret('news, updates')
@array_comma.interpret(['news,updates', 'alerts'], split: 1, flatten: true)
@array_comma.interpret('news,updates', split: false)
```

* `split` controls where strings are split:
  * `true` or `0`: split only a top-level string
  * `false`: do not split strings, only wrap
  * positive integer: split strings found at that array depth
  * `-1`: split strings found at any depth
* `flatten` controls whether split results stay nested at the point they were found or are promoted into the surrounding array.

Use `with(...)` to create variants with a different delimiter:

```ruby
@array_pipe = @array_comma.with(delimiter: '|')
```