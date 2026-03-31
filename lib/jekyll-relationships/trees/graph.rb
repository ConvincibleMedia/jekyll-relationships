# frozen_string_literal: true

require 'jekyll-relationships/trees/edge_builder'
require 'jekyll-relationships/trees/root_distances'

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
	def initialize(site:, configuration:, registry:, data_path:, debug_logger:, active_document_ids: nil)
		@site = site
		@configuration = configuration
		@registry = registry
		@data_path = data_path
		@debug_logger = debug_logger
		@active_document_ids = active_document_ids.nil? ? nil : active_document_ids.each_with_object({}) { |document_id, active_ids| active_ids[document_id] = true }
		@parents = Hash.new { |hash, key| hash[key] = [] }
		@children = Hash.new { |hash, key| hash[key] = [] }
		@parent_edge_entries = Hash.new { |hash, key| hash[key] = [] }
		@child_edge_entries = Hash.new { |hash, key| hash[key] = [] }
		@ancestor_cache = {}
		@descendant_cache = {}
		@root_distance_cache = nil
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
			data_path: @data_path,
			debug_logger: @debug_logger
		)
	end

	# Builds every configured tree edge.
	def build!
		@edge_builder.build!
	end

	# Returns one deep copy of the current tree graph state.
	def deep_dup
		duplicated_graph = self.class.new(
			site: @site,
			configuration: @configuration,
			registry: @registry,
			data_path: @data_path,
			debug_logger: @debug_logger,
			active_document_ids: @active_document_ids.nil? ? nil : @active_document_ids.keys
		)
		duplicated_graph.instance_variable_set(
			:@parents,
			duplicate_document_adjacency(@parents)
		)
		duplicated_graph.instance_variable_set(
			:@children,
			duplicate_document_adjacency(@children)
		)
		duplicated_graph.instance_variable_set(
			:@parent_edge_entries,
			duplicate_edge_entries(@parent_edge_entries)
		)
		duplicated_graph.instance_variable_set(
			:@child_edge_entries,
			duplicate_edge_entries(@child_edge_entries)
		)
		duplicated_graph
	end

	# Returns true when one document is part of any tree relationship.
	def participating?(document)
		@tree_collections.include?(document.collection.label)
	end

	# Returns true when the document is active in this graph.
	def active_document?(document)
		return true if @active_document_ids.nil?

		@active_document_ids.key?(document.object_id)
	end

	# Returns every active document for one collection.
	def documents_for(collection)
		@registry.documents_for(collection).select do |document|
			active_document?(document)
		end
	end

	# Returns immediate parents as canonical reference hashes.
	def parents_for(document, primary_path: nil)
		return [] unless active_document?(document)

		resolved_primary_path = resolve_primary_path(document: document, primary_path: primary_path)
		@parents[document].map { |parent| build_reference(parent, primary_path: resolved_primary_path) }
	end

	# Returns immediate children as canonical reference hashes.
	def children_for(document, primary_path: nil)
		return [] unless active_document?(document)

		resolved_primary_path = resolve_primary_path(document: document, primary_path: primary_path)
		@children[document].map { |child| build_reference(child, primary_path: resolved_primary_path) }
	end

	# Returns the immediate parent documents in deterministic insertion order.
	def parent_documents_for(document)
		return [] unless active_document?(document)

		@parents[document].dup
	end

	# Returns the immediate child documents in deterministic insertion order.
	def child_documents_for(document)
		return [] unless active_document?(document)

		@children[document].dup
	end

	# Returns metadata for each immediate parent edge in insertion order.
	def parent_edge_entries_for(document)
		return [] unless active_document?(document)

		@parent_edge_entries[document].map(&:dup)
	end

	# Returns metadata for each immediate child edge in insertion order.
	def child_edge_entries_for(document)
		return [] unless active_document?(document)

		@child_edge_entries[document].map(&:dup)
	end

	# Returns ancestor references filtered by minimum and maximum distance.
	def ancestors_for(document, primary_path: nil, min: 0, max: -1)
		return [] unless active_document?(document)

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
		return [] unless active_document?(document)

		resolved_primary_path = resolve_primary_path(document: document, primary_path: primary_path)
		filter_distances(
			distance_map_for(document: document, direction: :down),
			primary_path: resolved_primary_path,
			min: min,
			max: max
		)
	end

	# Returns the shortest number of edges from the document to any root.
	def root_distance_for(document)
		return nil unless active_document?(document)

		root_distances_for_graph[document.object_id]
	end

	# Adds one parent-child edge unless it would break tree guarantees.
	def add_edge(parent_document:, child_document:, tree_settings:, definition:, source_description:)
		return unless active_document?(parent_document) && active_document?(child_document)
		return if edge_exists?(parent_document: parent_document, child_document: child_document)

		if parent_document == child_document
			warn("Ignoring self-referential tree edge on `#{child_document.relative_path}`.")
			debug_tree_event(
				document: child_document,
				definition: definition,
				event: 'tree_edge_ignored',
				details: {
					reason: 'self_referential',
					source: source_description,
					parent: parent_document,
					child: child_document
				}
			)
			return
		end

		if maximum_reached?(maximum: tree_settings.max_parents, items: @parents[child_document])
			warn("Ignoring extra parent for `#{child_document.relative_path}` because the configured parent maximum has been reached.")
			debug_tree_event(
				document: child_document,
				definition: definition,
				event: 'tree_edge_ignored',
				details: {
					reason: 'max_parents_reached',
					source: source_description,
					parent: parent_document,
					child: child_document
				}
			)
			return
		end

		if maximum_reached?(maximum: tree_settings.max_children, items: @children[parent_document])
			warn("Ignoring extra child for `#{parent_document.relative_path}` because the configured child maximum has been reached.")
			debug_tree_event(
				document: parent_document,
				definition: definition,
				event: 'tree_edge_ignored',
				details: {
					reason: 'max_children_reached',
					source: source_description,
					parent: parent_document,
					child: child_document
				}
			)
			return
		end

		if reachable?(from_document: child_document, to_document: parent_document)
			warn("Ignoring tree edge from `#{parent_document.relative_path}` to `#{child_document.relative_path}` because it would create a loop.")
			debug_tree_event(
				document: child_document,
				definition: definition,
				event: 'tree_edge_ignored',
				details: {
					reason: 'loop_detected',
					source: source_description,
					parent: parent_document,
					child: child_document
				}
			)
			return
		end

		@parents[child_document] << parent_document
		@children[parent_document] << child_document
		@parent_edge_entries[child_document] << build_edge_entry(
			document: parent_document,
			definition: definition,
			tree_settings: tree_settings,
			source_description: source_description
		)
		@child_edge_entries[parent_document] << build_edge_entry(
			document: child_document,
			definition: definition,
			tree_settings: tree_settings,
			source_description: source_description
		)
		clear_traversal_cache
		debug_tree_event(
			document: child_document,
			definition: definition,
			event: 'tree_edge_added',
			details: {
				source: source_description,
				parent: parent_document,
				child: child_document
			}
		)
	end

	# Writes the final tree output back into document frontmatter.
	def write_back!
		@configuration.tree_relationships.each do |definition|
			write_definition_back!(definition)
		end
	end

	# Removes one document from the graph along with every adjacent edge.
	def remove_document!(document)
		return false unless active_document?(document)

		@active_document_ids.delete(document.object_id) unless @active_document_ids.nil?
		@children[document].dup.each do |child_document|
			remove_parent_edge(parent_document: document, child_document: child_document)
		end
		@parents[document].dup.each do |parent_document|
			remove_parent_edge(parent_document: parent_document, child_document: document)
		end
		@children.delete(document)
		@parents.delete(document)
		@child_edge_entries.delete(document)
		@parent_edge_entries.delete(document)
		clear_traversal_cache
		true
	end

	# Removes many documents from the graph.
	def remove_documents!(documents)
		Array(documents).each do |document|
			remove_document!(document)
		end
	end

	# Returns every document participating in tree relationships.
	def tree_documents
		@tree_collections.to_a.flat_map { |collection| documents_for(collection) }.uniq
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
			depth_value = root_distance_for(document)

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
						depth_value: depth_value,
						max_parents: definition.tree_settings.max_parents,
						max_children: definition.tree_settings.max_children
					)
				)
				debug_tree_event(
					document: document,
					definition: definition,
					event: 'tree_write_output',
					details: {
						path: frontmatter.output_path,
						value: @data_path.read(document.data, frontmatter.output_path)
					}
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
			@data_path.write(document.data, frontmatter.depth_output_path, depth_value)
			debug_tree_event(
				document: document,
				definition: definition,
				event: 'tree_write_output',
				details: {
					parent_path: definition.tree_settings.max_parents == 1 ? frontmatter.parent_output_path : frontmatter.parents_output_path,
					parent_value: definition.tree_settings.max_parents == 1 ? parent_values.first : parent_values,
					child_path: definition.tree_settings.max_children == 1 ? frontmatter.child_output_path : frontmatter.children_output_path,
					child_value: definition.tree_settings.max_children == 1 ? child_values.first : child_values,
					ancestors_path: frontmatter.ancestors_output_path,
					ancestors_value: ancestor_values,
					descendants_path: frontmatter.descendants_output_path,
					descendants_value: descendant_values,
					depth_path: frontmatter.depth_output_path,
					depth_value: depth_value
				}
			)
		end
	end

	# Returns the documents touched by one tree definition.
	def definition_documents(definition)
		[definition.from_collection, definition.to_collection].flat_map do |collection|
			documents_for(collection)
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

	# Removes one stored parent-child edge and its metadata in both directions.
	def remove_parent_edge(parent_document:, child_document:)
		@parents[child_document].delete(parent_document)
		@children[parent_document].delete(child_document)
		@parent_edge_entries[child_document].reject! do |entry|
			entry.fetch(:document) == parent_document
		end
		@child_edge_entries[parent_document].reject! do |entry|
			entry.fetch(:document) == child_document
		end
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

	# Computes one shortest-root-distance map for the current graph.
	def root_distances_for_graph
		@root_distance_cache ||= Trees::RootDistances.for(graph: self)
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
			key: @registry.key_for(document, primary_path: primary_path),
			include_count: false
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

	# Clears cached graph traversals after the tree changes.
	def clear_traversal_cache
		@ancestor_cache.clear
		@descendant_cache.clear
		@root_distance_cache = nil
	end

	# Captures the metadata needed to understand one stored edge later on.
	def build_edge_entry(document:, definition:, tree_settings:, source_description:)
		{
			document: document,
			definition: definition,
			tree_settings: tree_settings,
			source_description: source_description
		}
	end

	# Emits one Jekyll warning line for recoverable tree issues.
	def warn(message)
		Jekyll.logger.warn('Relationships:', message)
	end

	# Emits one debug line for tree processing when this definition opts in.
	def debug_tree_event(document:, definition:, event:, details:)
		@debug_logger.tree_event(
			document: document,
			definition: definition,
			area: 'trees',
			event: event,
			details: details
		)
	end

	# Duplicates one adjacency hash keyed by document.
	def duplicate_document_adjacency(adjacency)
		adjacency.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(document, neighbours), duplicated_adjacency|
			duplicated_adjacency[document] = neighbours.dup
		end
	end

	# Duplicates one edge-entry hash keyed by document.
	def duplicate_edge_entries(edge_entries)
		edge_entries.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(document, entries), duplicated_edge_entries|
			duplicated_edge_entries[document] = entries.map(&:dup)
		end
	end
end

end
end

end
end
