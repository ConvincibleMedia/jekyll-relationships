# frozen_string_literal: true

require 'jekyll-relationships/trees/frontmatter_paths'
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
		@path_configuration = FrontmatterPaths.new(
			global_frontmatter: @configuration.global_frontmatter,
			tree_settings: @configuration.tree_settings
		)
		@edge_builder = EdgeBuilder.new(
			graph: self,
			configuration: @configuration,
			registry: @registry,
			data_path: @data_path,
			path_configuration: @path_configuration
		)
	end

	# Builds every configured tree edge.
	def build!
		seed_primary_paths
		@edge_builder.build!
	end

	# Returns true when one document is part of any tree relationship.
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
		filter_distances(distance_map_for(document: document, direction: :up), min: min, max: max)
	end

	# Returns descendant references filtered by minimum and maximum distance.
	def descendants_for(document, min: 0, max: -1)
		filter_distances(distance_map_for(document: document, direction: :down), min: min, max: max)
	end

	# Adds one parent-child edge unless it would break tree guarantees.
	def add_edge(parent_document:, child_document:)
		return if edge_exists?(parent_document: parent_document, child_document: child_document)

		if parent_document == child_document
			warn("Ignoring self-referential tree edge on `#{child_document.relative_path}`.")
			return
		end

		if maximum_reached?(maximum: @configuration.tree_settings.max_parents, items: @parents[child_document])
			warn("Ignoring extra parent for `#{child_document.relative_path}` because the configured parent maximum has been reached.")
			return
		end

		if maximum_reached?(maximum: @configuration.tree_settings.max_children, items: @children[parent_document])
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
		tree_documents.each do |document|
			write_immediate_links(
				document: document,
				singular_path: @path_configuration.parent,
				plural_path: @path_configuration.parents,
				values: parents_for(document),
				maximum: @configuration.tree_settings.max_parents
			)
			write_immediate_links(
				document: document,
				singular_path: @path_configuration.child,
				plural_path: @path_configuration.children,
				values: children_for(document),
				maximum: @configuration.tree_settings.max_children
			)
			@data_path.write(document.data, @path_configuration.ancestors, ancestors_for(document, min: 0))
			@data_path.write(document.data, @path_configuration.descendants, descendants_for(document, min: 0))
		end
	end

	# Returns every document participating in tree relationships.
	def tree_documents
		@primary_path_by_collection.keys.flat_map { |collection| @registry.documents_for(collection) }.uniq
	end

	private

	# Captures the preferred primary path for each tree collection.
	def seed_primary_paths
		@configuration.tree_relationships.each do |definition|
			@primary_path_by_collection[definition.from_collection] ||= definition.primary_path
			@primary_path_by_collection[definition.to_collection] ||= definition.primary_path
		end
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
