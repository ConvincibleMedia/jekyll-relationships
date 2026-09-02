# frozen_string_literal: true

require 'jekyll-relationships/trees/root_distances'

module Jekyll
module Plugins

module Relationships
module Pruning

# Builds, repairs, and prunes the tree graph for one active document set.
#
# Each outer relationship round first runs this tree phase to convergence so
# normal resolvers always read the already-pruned tree. Orphan handling is part
# of the same phase because parent deletions can change both the visible tree
# structure and which documents survive into normal relationship resolution.
class TreePhase
	# Presents one mutable pruning view over one concrete tree graph.
	class TreeGraphView
		# Builds one mutable adjacency view from one tree graph.
		def initialize(tree_graph:)
			@tree_graph = tree_graph
			@documents_by_collection = Hash.new { |hash, key| hash[key] = {} }
			@parents = Hash.new { |hash, key| hash[key] = {} }
			@children = Hash.new { |hash, key| hash[key] = {} }
			@root_distance_cache = nil
			register_documents!
			register_edges!
		end

		# Returns every currently active document for one collection.
		def documents_for(collection)
			@documents_by_collection[collection].values
		end

		# Returns every currently active tree document.
		def tree_documents
			@documents_by_collection.values.flat_map(&:values)
		end

		# Returns the direct parent documents for one active document.
		def parent_documents_for(document)
			return [] unless active_document?(document)

			@parents[document].keys
		end

		# Returns the direct child documents for one active document.
		def child_documents_for(document)
			return [] unless active_document?(document)

			@children[document].keys
		end

		# Returns the shortest current distance from one document to any root.
		def root_distance_for(document)
			return nil unless active_document?(document)

			root_distances_for_graph[document.object_id]
		end

		# Returns the relevant neighbour documents for one configured tree member.
		def neighbour_documents_for_member(member:, document:, inverse:)
			return inverse_neighbours_for(member: member, document: document) if inverse

			direct_neighbours_for(member: member, document: document)
		end

		# Removes one document and every adjacent edge from the view.
		def remove_document(document)
			return false unless @documents_by_collection[document.collection.label].delete(document.object_id)

			@children[document].keys.each do |child_document|
				@parents[child_document].delete(document)
			end
			@parents[document].keys.each do |parent_document|
				@children[parent_document].delete(document)
			end
			@children.delete(document)
			@parents.delete(document)
			clear_root_distance_cache
			true
		end

		private

		# Registers every active tree document.
		def register_documents!
			@tree_graph.tree_documents.each do |document|
				@documents_by_collection[document.collection.label][document.object_id] = document
			end
		end

		# Registers one adjacency entry for every tree edge.
		def register_edges!
			@tree_graph.tree_documents.each do |document|
				@tree_graph.parent_documents_for(document).each do |parent_document|
					@parents[document][parent_document] = true
					@children[parent_document][document] = true
				end
			end
		end

		# Returns the direct tree neighbours for one subject document.
		def direct_neighbours_for(member:, document:)
			case member.mode
			when 'parent'
				filter_documents(@parents[document].keys, member.to_collection)
			when 'child'
				filter_documents(@children[document].keys, member.to_collection)
			when 'parent/child', 'child/parent'
				combine_documents(
					filter_documents(@parents[document].keys, member.to_collection),
					filter_documents(@children[document].keys, member.to_collection)
				)
			else
				[]
			end
		end

		# Returns the inverse tree neighbours for one subject document.
		def inverse_neighbours_for(member:, document:)
			case member.mode
			when 'parent'
				filter_documents(@children[document].keys, member.from_collection)
			when 'child'
				filter_documents(@parents[document].keys, member.from_collection)
			when 'parent/child', 'child/parent'
				combine_documents(
					filter_documents(@children[document].keys, member.from_collection),
					filter_documents(@parents[document].keys, member.from_collection)
				)
			else
				[]
			end
		end

		# Keeps only documents from the requested collection.
		def filter_documents(documents, collection)
			Array(documents).select { |document| document.collection.label == collection }
		end

		# Unions many document arrays while preserving the first encounter order.
		def combine_documents(*document_sets)
			document_sets.flatten.each_with_object({}) do |document, combined|
				combined[document.object_id] ||= document
			end.values
		end

		# Returns true when one document is still active in the mutable view.
		def active_document?(document)
			@documents_by_collection[document.collection.label].key?(document.object_id)
		end

		# Calculates the current root distances and caches them until the view changes.
		def root_distances_for_graph
			@root_distance_cache ||= Trees::RootDistances.for(graph: self)
		end

		# Clears the cached root distances after a structural tree change.
		def clear_root_distance_cache
			@root_distance_cache = nil
		end
	end

	# Builds one tree phase helper for one engine and one immutable provenance set.
	def initialize(engine:, provenance:)
		@engine = engine
		@configuration = engine.configuration
		@provenance = provenance
	end

	# Resolves tree pruning against one concrete tree seed graph.
	def process(seed_graph:)
		current_tree_graph = seed_graph.deep_dup
		removed_documents = []
		stabilise_orphans!(graph: current_tree_graph, removed_documents: removed_documents)
		return {
			graph: current_tree_graph,
			removed_documents: unique_documents(removed_documents)
		} if @configuration.tree_prune_rules.empty?

		loop do
			pruned_documents = prune_tree_rules(graph: current_tree_graph)
			if pruned_documents.empty?
				return {
					graph: current_tree_graph,
					removed_documents: unique_documents(removed_documents)
				}
			end

			current_tree_graph.remove_documents!(pruned_documents)
			removed_documents.concat(pruned_documents)
			stabilise_orphans!(graph: current_tree_graph, removed_documents: removed_documents)
		end
	end

	# Applies committed removals to one tree seed graph and repairs the tree.
	#
	# The tree seed only changes because documents have permanently died. Resolver
	# output never flows back into the seed, but structural repair such as orphan
	# reattachment must be reflected so the next round starts from the right tree.
	def apply_seed_removals(seed_graph:, documents:)
		documents_to_remove = Array(documents).select do |document|
			seed_graph.participating?(document) && seed_graph.active_document?(document)
		end
		return {
			seed_graph: seed_graph,
			removed_documents: [],
			seed_changed: false
		} if documents_to_remove.empty?

		next_seed_graph = seed_graph.deep_dup
		removed_documents = documents_to_remove.select do |document|
			next_seed_graph.remove_document!(document)
		end
		stabilise_orphans!(graph: next_seed_graph, removed_documents: removed_documents)

		{
			seed_graph: next_seed_graph,
			removed_documents: unique_documents(removed_documents),
			seed_changed: removed_documents.any?
		}
	end

	private

	# Removes or reattaches orphans until the graph stabilises.
	def stabilise_orphans!(graph:, removed_documents:)
		loop do
			orphan_result = apply_orphan_policy(graph: graph)
			orphaned_documents = orphan_result.fetch(:removed_documents)
			return graph if orphaned_documents.empty?

			graph.remove_documents!(orphaned_documents)
			removed_documents.concat(orphaned_documents)
		end
	end

	# Runs the configured tree prune rules against the current graph, re-reading
	# depth from the mutable graph view each time candidates are evaluated.
	def prune_tree_rules(graph:)
		RulePruner.new(
			graph: TreeGraphView.new(tree_graph: graph),
			rules: @configuration.tree_prune_rules,
			subject_documents_resolver: lambda do |rule, mutable_graph|
				mutable_graph.documents_for(rule.subject_collection).select do |document|
					depth = rule.depth
					depth.nil? || depth_selected?(depth: depth, root_distance: mutable_graph.root_distance_for(document))
				end
			end
		).prune!
	end

	# Returns true when one root distance is eligible under one configured depth.
	def depth_selected?(depth:, root_distance:)
		return false if root_distance.nil?

		if depth.positive?
			root_distance <= depth - 1
		else
			root_distance >= depth.abs
		end
	end

	# Applies the configured orphan policy to one current tree graph.
	def apply_orphan_policy(graph:)
		removed_documents = []
		orphan_documents(graph).each do |document|
			case @configuration.prune_settings.tree_orphans
			when 'orphan'
				next
			when 'prune'
				removed_documents << document
			when 'grandparents', 'grandparents required'
				next if reattach_orphan!(graph: graph, document: document)
				removed_documents << document if @configuration.prune_settings.tree_orphans == 'grandparents required'
			end
		end

		{
			graph: graph,
			removed_documents: removed_documents.uniq
		}
	end

	# Returns every currently orphaned document in deterministic order.
	def orphan_documents(graph)
		graph.tree_documents.select do |document|
			@provenance.original_parent_entries_for(document).any? && graph.parent_documents_for(document).empty?
		end.sort_by(&:relative_path)
	end

	# Attempts to reconnect one orphan to its nearest surviving original ancestors.
	def reattach_orphan!(graph:, document:)
		nearest_surviving_ancestor_candidates_for(graph: graph, document: document).each do |candidate|
			graph.add_edge(
				parent_document: candidate.fetch(:document),
				child_document: document,
				tree_settings: candidate.fetch(:tree_settings),
				definition: candidate.fetch(:definition),
				source_description: 'pruning ancestors'
			)
		end

		graph.parent_documents_for(document).any?
	end

	# Returns the first surviving ancestor on every original parent lineage.
	def nearest_surviving_ancestor_candidates_for(graph:, document:)
		@provenance.original_parent_entries_for(document).each_with_object({}) do |parent_entry, candidates|
			nearest_surviving_ancestors_for(
				graph: graph,
				document: parent_entry.fetch(:document),
				visited_document_ids: {}
			).each do |ancestor_document|
				candidates[ancestor_document.object_id] ||= {
					document: ancestor_document,
					definition: parent_entry.fetch(:definition),
					tree_settings: parent_entry.fetch(:tree_settings)
				}
			end
		end.values
	end

	# Walks removed provenance nodes until each lineage reaches an active document.
	def nearest_surviving_ancestors_for(graph:, document:, visited_document_ids:)
		return [] if visited_document_ids.key?(document.object_id)
		return [document] if graph.active_document?(document)

		lineage_visited_document_ids = visited_document_ids.merge(document.object_id => true)
		@provenance.original_parent_entries_for(document).each_with_object({}) do |parent_entry, ancestors|
			nearest_surviving_ancestors_for(
				graph: graph,
				document: parent_entry.fetch(:document),
				visited_document_ids: lineage_visited_document_ids
			).each do |ancestor_document|
				ancestors[ancestor_document.object_id] ||= ancestor_document
			end
		end.values
	end

	# Returns one document array with later duplicates removed by object id.
	def unique_documents(documents)
		Array(documents).each_with_object({}) do |document, unique_documents|
			unique_documents[document.object_id] ||= document
		end.values
	end
end

end
end

end
end
