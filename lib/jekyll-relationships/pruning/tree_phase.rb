# frozen_string_literal: true

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
			register_documents!
			register_edges!
		end

		# Returns every currently active document for one collection.
		def documents_for(collection)
			@documents_by_collection[collection].values
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
	end

	# Builds one tree phase helper for one engine and one immutable provenance set.
	def initialize(engine:, provenance:)
		@engine = engine
		@configuration = engine.configuration
		@provenance = provenance
	end

	# Builds the pruned tree graph for one active document set.
	def process(active_document_ids:)
		current_active_document_ids = active_document_ids.dup
		removed_documents = []
		@current_active_document_ids = active_document_lookup(current_active_document_ids)
		orphan_result = stabilise_orphans!(
			current_active_document_ids: current_active_document_ids,
			removed_documents: removed_documents
		)
		current_tree_graph = orphan_result.fetch(:graph)
		return {
			tree_graph: current_tree_graph,
			active_document_ids: current_active_document_ids,
			removed_documents: removed_documents
		} if @configuration.tree_prune_rules.empty?

		eligible_document_ids_by_rule = eligible_document_ids_by_rule(graph: current_tree_graph)

		loop do
			pruned_documents = prune_tree_rules(
				graph: current_tree_graph,
				eligible_document_ids_by_rule: eligible_document_ids_by_rule
			)
			if pruned_documents.empty?
				return {
					tree_graph: current_tree_graph,
					active_document_ids: current_active_document_ids,
					removed_documents: removed_documents
				}
			end

			remove_documents!(
				current_active_document_ids: current_active_document_ids,
				documents: pruned_documents
			)
			removed_documents.concat(pruned_documents)
			current_tree_graph = stabilise_orphans!(
				current_active_document_ids: current_active_document_ids,
				removed_documents: removed_documents
			).fetch(:graph)
		end
	end

	private

	# Rebuilds the tree graph until orphan handling no longer removes documents.
	def stabilise_orphans!(current_active_document_ids:, removed_documents:)
		loop do
			@current_active_document_ids = active_document_lookup(current_active_document_ids)
			base_graph = build_tree_graph(active_document_ids: current_active_document_ids)
			orphan_result = apply_orphan_policy(graph: base_graph)
			orphaned_documents = orphan_result.fetch(:removed_documents)
			return {
				graph: orphan_result.fetch(:graph)
			} if orphaned_documents.empty?

			remove_documents!(
				current_active_document_ids: current_active_document_ids,
				documents: orphaned_documents
			)
			removed_documents.concat(orphaned_documents)
		end
	end

	# Builds one fresh tree graph for the current active document set.
	def build_tree_graph(active_document_ids:)
		tree_graph = Trees::Graph.new(
			site: @engine.site,
			configuration: @configuration,
			registry: @engine.registry,
			data_path: @engine.data_path,
			debug_logger: @engine.debug_logger,
			active_document_ids: active_document_ids
		)
		tree_graph.build!
		tree_graph
	end

	# Builds one stable lookup of which documents each tree rule may prune.
	def eligible_document_ids_by_rule(graph:)
		root_distances = root_distances_for(graph)
		@configuration.tree_prune_rules.each_with_object({}) do |rule, lookup|
			lookup[rule.object_id] = graph.documents_for(rule.subject_collection).each_with_object({}) do |document, eligible_documents|
				next unless depth_selected?(depth: rule.depth, root_distance: root_distances[document.object_id])

				eligible_documents[document.object_id] = true
			end
		end
	end

	# Runs the configured tree prune rules against the current graph while only
	# allowing the documents selected by the initial depth snapshot to be pruned.
	def prune_tree_rules(graph:, eligible_document_ids_by_rule:)
		RulePruner.new(
			graph: TreeGraphView.new(tree_graph: graph),
			rules: @configuration.tree_prune_rules,
			subject_documents_resolver: lambda do |rule, mutable_graph|
				eligible_document_ids = eligible_document_ids_by_rule.fetch(rule.object_id)
				mutable_graph.documents_for(rule.subject_collection).select do |document|
					eligible_document_ids.key?(document.object_id)
				end
			end
		).prune!
	end

	# Calculates the shortest distance from every node to any root in the current tree.
	def root_distances_for(graph)
		root_distances = {}
		queue = graph.tree_documents.select do |document|
			graph.parent_documents_for(document).empty?
		end.sort_by(&:relative_path).map do |root_document|
			[root_document, 0]
		end

		until queue.empty?
			document, distance = queue.shift
			existing_distance = root_distances[document.object_id]
			next if !existing_distance.nil? && existing_distance <= distance

			root_distances[document.object_id] = distance
			graph.child_documents_for(document).each do |child_document|
				queue << [child_document, distance + 1]
			end
		end

		root_distances
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

	# Removes many documents from the current active set in place.
	def remove_documents!(current_active_document_ids:, documents:)
		Array(documents).each do |document|
			current_active_document_ids.delete(document.object_id)
			@current_active_document_ids.delete(document.object_id)
		end
	end

	# Builds one fast active-document lookup for the current build state.
	def active_document_lookup(active_document_ids)
		active_document_ids.each_with_object({}) do |document_id, active_ids|
			active_ids[document_id] = true
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

	# Attempts to reconnect one orphan to its surviving original grandparents.
	def reattach_orphan!(graph:, document:)
		grandparent_candidates_for(document).each do |candidate|
			graph.add_edge(
				parent_document: candidate.fetch(:document),
				child_document: document,
				tree_settings: candidate.fetch(:tree_settings),
				definition: candidate.fetch(:definition),
				source_description: 'pruning grandparents'
			)
		end

		graph.parent_documents_for(document).any?
	end

	# Returns every surviving grandparent candidate for one orphan.
	def grandparent_candidates_for(document)
		@provenance.original_parent_entries_for(document).each_with_object({}) do |parent_entry, candidates|
			@provenance.original_parent_entries_for(parent_entry.fetch(:document)).each do |grandparent_entry|
				grandparent_document = grandparent_entry.fetch(:document)
				next unless current_document?(grandparent_document)

				candidates[grandparent_document.object_id] ||= {
					document: grandparent_document,
					definition: parent_entry.fetch(:definition),
					tree_settings: parent_entry.fetch(:tree_settings)
				}
			end
		end.values
	end

	# Returns true when one document is still active in the current build.
	def current_document?(document)
		@current_active_document_ids.key?(document.object_id)
	end
end

end
end

end
end
