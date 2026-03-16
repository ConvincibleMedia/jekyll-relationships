# frozen_string_literal: true

require 'jekyll-relationships/trees/edge_builder'

module Jekyll
module Plugins

module Relationships
module Trees

# Builds and exposes all tree relationships for the site.
#
# Tree processing is eager so ancestry queries stay cheap and recursion-free
# once normal relationship resolvers begin running.
class Graph
	# Builds one tree graph helper with the collaborators it needs.
	def initialize(site:, configuration:, registry:, data_path:)
		@site = site
		@configuration = configuration
		@registry = registry
		@data_path = data_path
		@parents = Hash.new { |hash, key| hash[key] = [] }
		@children = Hash.new { |hash, key| hash[key] = [] }
		@ancestor_cache = {}
		@descendant_cache = {}
		@primary_path_by_collection = {}
		@tree_collections = @configuration.tree_relationships.each_with_object(Set.new) do |definition, collections|
			collections << definition.from_collection
			collections << definition.to_collection
			@primary_path_by_collection[definition.from_collection] ||= definition.primary_path
			@primary_path_by_collection[definition.to_collection] ||= definition.primary_path
		end
		@edge_builder = EdgeBuilder.new(
			graph: self,
			configuration: @configuration,
			registry: @registry,
			data_path: @data_path
		)
	end

	# Builds every configured tree edge.
	def build!
		@edge_builder.build!
	end

	# Returns true when one document is part of any tree relationship.
	def participating?(document)
		@tree_collections.include?(document.collection.label)
	end

	# Returns immediate parents as canonical reference hashes.
	def parents_for(document, primary_path: nil)
		resolved_primary_path = resolve_primary_path(document: document, primary_path: primary_path)
		@parents[document].map { |parent| build_reference(parent, primary_path: resolved_primary_path) }
	end

	# Returns immediate children as canonical reference hashes.
	def children_for(document, primary_path: nil)
		resolved_primary_path = resolve_primary_path(document: document, primary_path: primary_path)
		@children[document].map { |child| build_reference(child, primary_path: resolved_primary_path) }
	end

	# Returns ancestor references filtered by minimum and maximum distance.
	def ancestors_for(document, primary_path: nil, min: 0, max: -1)
		resolved_primary_path = resolve_primary_path(document: document, primary_path: primary_path)
		filter_distances(
			distance_map_for(document: document, direction: :up),
			primary_path: resolved_primary_path,
			min: min,
			max: max
		)
	end

	# Returns descendant references filtered by minimum and maximum distance.
	def descendants_for(document, primary_path: nil, min: 0, max: -1)
		resolved_primary_path = resolve_primary_path(document: document, primary_path: primary_path)
		filter_distances(
			distance_map_for(document: document, direction: :down),
			primary_path: resolved_primary_path,
			min: min,
			max: max
		)
	end

	# Adds one parent-child edge unless it would break tree guarantees.
	def add_edge(parent_document:, child_document:, tree_settings:)
		return if edge_exists?(parent_document: parent_document, child_document: child_document)

		if parent_document == child_document
			warn("Ignoring self-referential tree edge on `#{child_document.relative_path}`.")
			return
		end

		if maximum_reached?(maximum: tree_settings.max_parents, items: @parents[child_document])
			warn("Ignoring extra parent for `#{child_document.relative_path}` because the configured parent maximum has been reached.")
			return
		end

		if maximum_reached?(maximum: tree_settings.max_children, items: @children[parent_document])
			warn("Ignoring extra child for `#{parent_document.relative_path}` because the configured child maximum has been reached.")
			return
		end

		if reachable?(from_document: child_document, to_document: parent_document)
			warn("Ignoring tree edge from `#{parent_document.relative_path}` to `#{child_document.relative_path}` because it would create a loop.")
			return
		end

		@parents[child_document] << parent_document
		@children[parent_document] << child_document
		clear_distance_cache
	end

	# Writes the final tree output back into document frontmatter.
	def write_back!
		@configuration.tree_relationships.each do |definition|
			write_definition_back!(definition)
		end
	end

	# Returns every document participating in tree relationships.
	def tree_documents
		@tree_collections.to_a.flat_map { |collection| @registry.documents_for(collection) }.uniq
	end

	private

	# Writes tree output for one concrete relationship definition.
	def write_definition_back!(definition)
		frontmatter = definition.tree_settings.frontmatter

		definition_documents(definition).each do |document|
			parent_values = parents_for(document, primary_path: definition.primary_path)
			child_values = children_for(document, primary_path: definition.primary_path)
			ancestor_values = ancestors_for(document, primary_path: definition.primary_path, min: 0)
			descendant_values = descendants_for(document, primary_path: definition.primary_path, min: 0)

			if frontmatter.output_path
				@data_path.write(
					document.data,
					frontmatter.output_path,
					frontmatter.output_payload(
						parent_value: parent_values.first,
						parents_value: parent_values,
						child_value: child_values.first,
						children_value: child_values,
						ancestors_value: ancestor_values,
						descendants_value: descendant_values,
						max_parents: definition.tree_settings.max_parents,
						max_children: definition.tree_settings.max_children
					)
				)
				next
			end

			write_immediate_links(
				document: document,
				singular_path: frontmatter.parent_output_path,
				plural_path: frontmatter.parents_output_path,
				values: parent_values,
				maximum: definition.tree_settings.max_parents
			)
			write_immediate_links(
				document: document,
				singular_path: frontmatter.child_output_path,
				plural_path: frontmatter.children_output_path,
				values: child_values,
				maximum: definition.tree_settings.max_children
			)
			@data_path.write(document.data, frontmatter.ancestors_output_path, ancestor_values)
			@data_path.write(document.data, frontmatter.descendants_output_path, descendant_values)
		end
	end

	# Returns the documents touched by one tree definition.
	def definition_documents(definition)
		[definition.from_collection, definition.to_collection].flat_map do |collection|
			@registry.documents_for(collection)
		end.uniq
	end

	# Chooses the requested primary path, or the collection's first configured
	# tree primary path when callers use the public helper API without one.
	def resolve_primary_path(document:, primary_path:)
		return primary_path unless primary_path.nil?

		@primary_path_by_collection[document.collection.label]
	end

	# Returns true when one edge already exists.
	def edge_exists?(parent_document:, child_document:)
		@parents[child_document].include?(parent_document)
	end

	# Returns true when one collection has already reached its configured cap.
	def maximum_reached?(maximum:, items:)
		maximum != -1 && items.length >= maximum
	end

	# Returns true when there is already a path from one document to another.
	def reachable?(from_document:, to_document:)
		queue = [from_document]
		visited = Set.new

		until queue.empty?
			current_document = queue.shift
			return true if current_document == to_document
			next if visited.include?(current_document.object_id)

			visited << current_document.object_id
			queue.concat(@children[current_document])
		end

		false
	end

	# Computes one ancestor or descendant distance map with shortest paths.
	def distance_map_for(document:, direction:)
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
	def filter_distances(distance_map, primary_path:, min:, max:)
		distance_map.each_with_object([]) do |(document, distance), references|
			next if distance < min
			next if max != -1 && distance > max

			references << build_reference(document, primary_path: primary_path, distance: distance)
		end
	end

	# Builds one canonical reference hash, optionally including distance.
	def build_reference(document, primary_path:, distance: nil)
		reference = @configuration.reference_template.build(
			document: document,
			key: @registry.key_for(document, primary_path: primary_path)
		)
		reference['distance'] = distance unless distance.nil?
		reference
	end

	# Writes one immediate parent or child output in singular or plural form.
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

	# Emits one Jekyll warning line for recoverable tree issues.
	def warn(message)
		Jekyll.logger.warn('Relationships:', message)
	end
end

end
end

end
end
