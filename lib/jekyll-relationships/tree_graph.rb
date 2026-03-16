# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

# Builds and exposes all tree relationships for the site.
#
# Tree processing is eager because ancestry queries should be cheap and
# recursion-free once the normal relationship resolvers start running.
class TreeGraph

	# Builds the graph helper with all collaborators it needs.
	def initialize(site:, configuration:, registry:, data_path:)
		@site = site
		@configuration = configuration
		@registry = registry
		@data_path = data_path
		@string_array = Jekyll::Plugins::Support::StringArray.new
		@parents = Hash.new { |hash, key| hash[key] = [] }
		@children = Hash.new { |hash, key| hash[key] = [] }
		@ancestor_cache = {}
		@descendant_cache = {}
		@primary_path_by_collection = {}
	end

	# Builds all configured tree edges.
	def build!
		seed_primary_paths
		build_frontmatter_edges
		build_url_edges if @configuration.tree_settings.fetch('url')
	end

	# Returns true when the document is part of any tree relationship.
	def participating?(document)
		@primary_path_by_collection.key?(document.collection.label)
	end

	# Returns immediate parents as canonical reference hashes.
	def parents_for(document)
		@parents[document].map { |parent| build_reference(parent) }
	end

	# Returns immediate children as canonical reference hashes.
	def children_for(document)
		@children[document].map { |child| build_reference(child) }
	end

	# Returns ancestor references filtered by minimum and maximum distance.
	def ancestors_for(document, min: 0, max: -1)
		filter_distances(distance_map_for(document, direction: :up), min: min, max: max)
	end

	# Returns descendant references filtered by minimum and maximum distance.
	def descendants_for(document, min: 0, max: -1)
		filter_distances(distance_map_for(document, direction: :down), min: min, max: max)
	end

	# Writes the final tree output back into document frontmatter.
	def write_back!
		tree_frontmatter = resolved_tree_frontmatter
		maximums = @configuration.tree_settings.fetch('max')
		tree_documents.each do |document|
			write_immediate_links(
				document: document,
				singular_path: tree_frontmatter.fetch('parent'),
				plural_path: tree_frontmatter.fetch('parents'),
				values: parents_for(document),
				maximum: maximums.fetch('parents')
			)
			write_immediate_links(
				document: document,
				singular_path: tree_frontmatter.fetch('child'),
				plural_path: tree_frontmatter.fetch('children'),
				values: children_for(document),
				maximum: maximums.fetch('children')
			)
			@data_path.write(document.data, tree_frontmatter.fetch('ancestors'), ancestors_for(document, min: 0))
			@data_path.write(document.data, tree_frontmatter.fetch('descendants'), descendants_for(document, min: 0))
		end
	end

	private

	# Captures the preferred primary path for each tree collection.
	def seed_primary_paths
		@configuration.tree_relationships.each do |definition|
			@primary_path_by_collection[definition.from_collection] ||= definition.primary_path
			@primary_path_by_collection[definition.to_collection] ||= definition.primary_path
		end
	end

	# Reads all parent and child references from frontmatter.
	def build_frontmatter_edges
		@configuration.tree_relationships.each do |definition|
			definition.parent_child_pairs.each do |parent_collection, child_collection|
				read_parent_references(definition, parent_collection, child_collection)
				read_child_references(definition, parent_collection, child_collection)
			end
		end
	end

	# Reads parent references from child documents.
	def read_parent_references(definition, parent_collection, child_collection)
		parent_paths = active_parent_input_paths
		@registry.documents_for(child_collection).each do |child_document|
			parent_paths.each do |path|
				parse_references(@data_path.read(child_document.data, path)).each do |reference|
					parent_document = resolve_reference(reference, definition.primary_path)
					next unless parent_document
					next unless parent_document.collection.label == parent_collection

					add_edge(parent_document, child_document)
				end
			end
		end
	end

	# Reads child references from parent documents.
	def read_child_references(definition, parent_collection, child_collection)
		child_paths = active_child_input_paths
		@registry.documents_for(parent_collection).each do |parent_document|
			child_paths.each do |path|
				parse_references(@data_path.read(parent_document.data, path)).each do |reference|
					child_document = resolve_reference(reference, definition.primary_path)
					next unless child_document
					next unless child_document.collection.label == child_collection

					add_edge(parent_document, child_document)
				end
			end
		end
	end

	# Adds URL-derived tree edges.
	def build_url_edges
		url_index = build_url_index
		@configuration.tree_relationships.each do |definition|
			definition.parent_child_pairs.each do |parent_collection, child_collection|
				@registry.documents_for(child_collection).each do |child_document|
					parts = normalised_url_parts(child_document)
					next if parts.length <= 1

					parent_parts = parts[0...-1]
					parents = fetch_nested(url_index, parent_collection, parent_parts)
					next unless parents

					parents.each do |parent_document|
						add_edge(parent_document, child_document)
					end
				end
			end
		end
	end

	# Builds a lookup from collection plus normalised URL parts to documents.
	def build_url_index
		tree_documents.each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |document, index|
			collection = document.collection.label
			parts = normalised_url_parts(document)
			index[collection][parts] ||= []
			index[collection][parts] << document
		end
	end

	# Normalises one document URL into its path segments.
	def normalised_url_parts(document)
		document.url.to_s.sub(%r{\A/+}, '').sub(%r{/+index\.html\z}, '').sub(%r{/+\z}, '').split('/').reject(&:empty?)
	end

	# Adds one parent-child edge unless it would break tree guarantees.
	def add_edge(parent_document, child_document)
		return if edge_exists?(parent_document, child_document)

		if parent_document == child_document
			warn("Ignoring self-referential tree edge on `#{child_document.relative_path}`.")
			return
		end

		if maximum_reached?(@configuration.tree_settings.fetch('max').fetch('parents'), @parents[child_document])
			warn("Ignoring extra parent for `#{child_document.relative_path}` because the configured parent maximum has been reached.")
			return
		end

		if maximum_reached?(@configuration.tree_settings.fetch('max').fetch('children'), @children[parent_document])
			warn("Ignoring extra child for `#{parent_document.relative_path}` because the configured child maximum has been reached.")
			return
		end

		if reachable?(child_document, parent_document)
			warn("Ignoring tree edge from `#{parent_document.relative_path}` to `#{child_document.relative_path}` because it would create a loop.")
			return
		end

		@parents[child_document] << parent_document
		@children[parent_document] << child_document
		clear_distance_cache
	end

	# Returns true when the edge already exists.
	def edge_exists?(parent_document, child_document)
		@parents[child_document].include?(parent_document)
	end

	# Returns true when the collection has already reached its configured cap.
	def maximum_reached?(maximum, collection)
		maximum != -1 && collection.length >= maximum
	end

	# Returns true when there is already a path from `from_document` to `to_document`.
	def reachable?(from_document, to_document)
		queue = [from_document]
		visited = Set.new

		until queue.empty?
			current = queue.shift
			return true if current == to_document
			next if visited.include?(current.object_id)

			visited << current.object_id
			queue.concat(@children[current])
		end

		false
	end

	# Parses one frontmatter tree value into parsed references.
	def parse_references(value)
		@string_array.interpret(value, split: -1, flatten: true).map do |entry|
			@configuration.reference_template.parse(entry)
		end.compact
	end

	# Resolves one parsed reference to a document.
	def resolve_reference(reference, primary_path)
		return reference.page if reference.document?

		collection = reference.collection.to_s unless reference.collection.nil?
		@registry.lookup(
			key: reference.key,
			primary_path: primary_path,
			collection: collection
		)
	end

	# Computes one ancestor or descendant distance map with shortest paths.
	def distance_map_for(document, direction:)
		cache = direction == :up ? @ancestor_cache : @descendant_cache
		return cache[document] if cache.key?(document)

		neighbours = direction == :up ? @parents : @children
		queue = [[document, 0]]
		visited = {}
		ordered = []

		until queue.empty?
			current_document, distance = queue.shift
			next if visited.key?(current_document.object_id)

			visited[current_document.object_id] = distance
			ordered << [current_document, distance]
			neighbours[current_document].each do |next_document|
				queue << [next_document, distance + 1]
			end
		end

		cache[document] = ordered
	end

	# Filters one distance map to the requested range and builds references.
	def filter_distances(distance_map, min:, max:)
		distance_map.each_with_object([]) do |(document, distance), references|
			next if distance < min
			next if max != -1 && distance > max

			references << build_reference(document, distance)
		end
	end

	# Builds one canonical reference hash, optionally including distance.
	def build_reference(document, distance = nil)
		primary_path = @primary_path_by_collection[document.collection.label]
		reference = @configuration.reference_template.build(
			document: document,
			key: @registry.key_for(document, primary_path: primary_path)
		)
		reference['distance'] = distance unless distance.nil?
		reference
	end

	# Writes one immediate parent/child output in singular or plural form.
	def write_immediate_links(document:, singular_path:, plural_path:, values:, maximum:)
		if maximum == 1
			@data_path.write(document.data, singular_path, values.first)
		else
			@data_path.write(document.data, plural_path, values)
		end
	end

	# Clears cached breadth-first-search results after a new edge is added.
	def clear_distance_cache
		@ancestor_cache.clear
		@descendant_cache.clear
	end

	# Returns all documents in tree collections.
	def tree_documents
		@primary_path_by_collection.keys.flat_map { |collection| @registry.documents_for(collection) }.uniq
	end

	# Returns the configured parent input paths.
	def active_parent_input_paths
		tree_frontmatter = resolved_tree_frontmatter
		if @configuration.tree_settings.fetch('max').fetch('parents') == 1
			[tree_frontmatter.fetch('parent')]
		else
			[tree_frontmatter.fetch('parent'), tree_frontmatter.fetch('parents')].uniq
		end
	end

	# Returns the configured child input paths.
	def active_child_input_paths
		tree_frontmatter = resolved_tree_frontmatter
		if @configuration.tree_settings.fetch('max').fetch('children') == 1
			[tree_frontmatter.fetch('child')]
		else
			[tree_frontmatter.fetch('child'), tree_frontmatter.fetch('children')].uniq
		end
	end

	# Reads one nested hash value without creating a default entry.
	def fetch_nested(hash, first_key, second_key)
		first_hash = hash[first_key]
		return nil unless first_hash

		first_hash[second_key]
	end

	# Emits one Jekyll warning line for recoverable tree issues.
	def warn(message)
		Jekyll.logger.warn('Relationships:', message)
	end

	# Applies the normal relationship base path to tree frontmatter keys.
	def resolved_tree_frontmatter
		base = @configuration.global_frontmatter.fetch('base').to_s
		@configuration.tree_settings.fetch('frontmatter').each_with_object({}) do |(name, path), resolved|
			resolved[name] = if base.empty?
											 path
										 else
											 "#{base}.#{path}"
										 end
		end
	end
end

end

end
end
