# frozen_string_literal: true

require 'jekyll-relationships/engine/session'
require 'jekyll-relationships/engine/raw_path_state'
require 'jekyll-relationships/engine/relationship_state'
require 'jekyll-relationships/engine/normal_seed'
require 'jekyll-relationships/engine/persisted_links'
require 'jekyll-relationships/engine/write_back'
require 'jekyll-relationships/trees/graph'

module Jekyll
module Plugins

module Relationships

# Orchestrates iterative tree building, relationship resolution, pruning, and
# final write-back.
#
# One engine instance handles one Jekyll build and owns the immutable site-wide
# collaborators reused across many rebuild rounds. Each resolution round runs in
# a fresh session so resolver and write-back caches never outlive the graph they
# were built against.
class Engine
	attr_reader :site, :configuration, :registry, :data_path, :debug_logger

	# Builds one engine for one Jekyll site build.
	def initialize(site:)
		@site = site
		@configuration = Configuration.new(@site.config)
		return unless @configuration.enabled?

		@debug_logger = DebugLogger.new(
			reference_key_property: @configuration.reference_template.key_property
		)
		@run_logger = RunLogger.new
		@registry = Documents::Registry.new(site: @site, collections: @configuration.collections)
		@data_path = Jekyll::Plugins::Relationships::Support::DataPath.new
	end

	# Processes the whole site.
	def process!
		return unless @configuration.enabled?
		return if @configuration.collections.empty?

		@registry.validate_collections!
		@registry.validate_primary_paths!(primary_paths: @configuration.primary_paths)
		initial_active_document_ids = all_active_document_ids
		initial_tree_seed_graph = build_tree_graph(active_document_ids: initial_active_document_ids)
		normal_seed = NormalSeed.new(engine: self, active_document_ids: initial_active_document_ids)
		persisted_links = PersistedLinks.new(engine: self)
		final_result = final_result_for(
			initial_active_document_ids: initial_active_document_ids,
			initial_tree_seed_graph: initial_tree_seed_graph,
			normal_seed: normal_seed,
			persisted_links: persisted_links
		)
		final_session = final_result.fetch(:session)
		final_tree_graph = final_result.fetch(:tree_graph)
		final_normal_graph = Pruning::NormalGraph.new(session: final_session)

		log_relationship_summary(
			session: final_session,
			normal_graph: final_normal_graph,
			tree_graph: final_tree_graph
		)
		@run_logger.pruning_summary(
			removed_documents_by_collection: removed_documents_by_collection(final_result.fetch(:removed_documents))
		) if @configuration.pruning_enabled?

		final_session.write_back!
		final_tree_graph.write_back!
		remove_inactive_documents!(active_document_ids: final_result.fetch(:active_document_ids))
		@run_logger.finish!
	end

	private

	# Returns every participating document object id in the site.
	def all_active_document_ids
		@configuration.collections.flat_map do |collection|
			@registry.documents_for(collection)
		end.map(&:object_id).uniq
	end

	# Builds one fresh tree graph for one active document set.
	def build_tree_graph(active_document_ids:)
		tree_graph = Trees::Graph.new(
			site: @site,
			configuration: @configuration,
			registry: @registry,
			data_path: @data_path,
			debug_logger: @debug_logger,
			active_document_ids: active_document_ids
		)
		tree_graph.build!
		tree_graph
	end

	# Returns the final active graphs, either directly or via prune iteration.
	def final_result_for(initial_active_document_ids:, initial_tree_seed_graph:, normal_seed:, persisted_links:)
		return resolved_result_for(
			active_document_ids: initial_active_document_ids,
			tree_graph: initial_tree_seed_graph.deep_dup,
			normal_seed: normal_seed,
			persisted_links: persisted_links,
			removed_documents: []
		) unless @configuration.pruning_enabled?

		prune_result_for(
			initial_active_document_ids: initial_active_document_ids,
			initial_tree_seed_graph: initial_tree_seed_graph,
			normal_seed: normal_seed,
			persisted_links: persisted_links
		)
	end

	# Runs the configured prune rounds and returns the final active graphs.
	def prune_result_for(initial_active_document_ids:, initial_tree_seed_graph:, normal_seed:, persisted_links:)
		tree_phase = Pruning::TreePhase.new(
			engine: self,
			provenance: Pruning::TreeProvenance.new(tree_graph: initial_tree_seed_graph)
		)
		current_active_document_ids = initial_active_document_ids.dup
		current_tree_seed_graph = initial_tree_seed_graph
		removed_documents = {}

		@configuration.prune_settings.prune_rounds.times do
			tree_phase_result = tree_phase.process(seed_graph: current_tree_seed_graph)
			tree_seed_update = apply_removed_documents_to_seeds!(
				tree_phase: tree_phase,
				tree_seed_graph: current_tree_seed_graph,
				normal_seed: normal_seed,
				persisted_links: persisted_links,
				current_active_document_ids: current_active_document_ids,
				documents: tree_phase_result.fetch(:removed_documents)
			)
			current_tree_seed_graph = tree_seed_update.fetch(:tree_seed_graph)
			register_removed_documents!(
				removed_documents: removed_documents,
				documents: tree_seed_update.fetch(:removed_documents)
			)

			session = build_session(
				active_document_ids: current_active_document_ids,
				tree_graph: tree_phase_result.fetch(:graph),
				normal_seed: normal_seed,
				persisted_links: persisted_links
			)
			session.resolve_all_relationships!

			normal_removed_documents = Pruning::RulePruner.new(
				graph: Pruning::NormalGraph.new(session: session),
				rules: @configuration.normal_prune_rules
			).prune!
			if normal_removed_documents.empty? && !tree_seed_changes_require_iteration?(tree_seed_update)
				return {
					active_document_ids: current_active_document_ids,
					removed_documents: removed_documents.values,
					tree_graph: tree_phase_result.fetch(:graph),
					session: session
				}
			end

			normal_seed_update = apply_removed_documents_to_seeds!(
				tree_phase: tree_phase,
				tree_seed_graph: current_tree_seed_graph,
				normal_seed: normal_seed,
				persisted_links: persisted_links,
				current_active_document_ids: current_active_document_ids,
				documents: normal_removed_documents
			)
			current_tree_seed_graph = normal_seed_update.fetch(:tree_seed_graph)
			register_removed_documents!(
				removed_documents: removed_documents,
				documents: normal_seed_update.fetch(:removed_documents)
			)
		end

		resolved_result_for(
			active_document_ids: current_active_document_ids,
			tree_graph: current_tree_seed_graph.deep_dup,
			normal_seed: normal_seed,
			persisted_links: persisted_links,
			removed_documents: removed_documents.values
		)
	end

	# Builds one final resolved session for the currently surviving seeds.
	def resolved_result_for(active_document_ids:, tree_graph:, normal_seed:, persisted_links:, removed_documents:)
		session = build_session(
			active_document_ids: active_document_ids,
			tree_graph: tree_graph,
			normal_seed: normal_seed,
			persisted_links: persisted_links
		)
		session.resolve_all_relationships!
		{
			active_document_ids: active_document_ids,
			removed_documents: removed_documents,
			tree_graph: tree_graph,
			session: session
		}
	end

	# Builds one normal-resolution session for one active graph snapshot.
	def build_session(active_document_ids:, tree_graph:, normal_seed:, persisted_links:)
		Session.new(
			engine: self,
			active_document_ids: active_document_ids,
			tree_graph: tree_graph,
			normal_seed: normal_seed,
			persisted_links: persisted_links
		)
	end

	# Applies removals to both seeds and returns the updated tree seed graph.
	def apply_removed_documents_to_seeds!(tree_phase:, tree_seed_graph:, normal_seed:, persisted_links:, current_active_document_ids:, documents:)
		requested_removed_documents = unique_documents(documents)
		remove_from_normal_side!(
			normal_seed: normal_seed,
			persisted_links: persisted_links,
			current_active_document_ids: current_active_document_ids,
			documents: requested_removed_documents
		)
		tree_seed_result = tree_phase.apply_seed_removals(
			seed_graph: tree_seed_graph,
			documents: requested_removed_documents
		)
		extra_tree_removed_documents = unique_documents(
			tree_seed_result.fetch(:removed_documents).reject do |document|
				requested_removed_documents.any? { |requested_document| requested_document.object_id == document.object_id }
			end
		)
		remove_from_normal_side!(
			normal_seed: normal_seed,
			persisted_links: persisted_links,
			current_active_document_ids: current_active_document_ids,
			documents: extra_tree_removed_documents
		)

		{
			tree_seed_graph: tree_seed_result.fetch(:seed_graph),
			removed_documents: unique_documents(requested_removed_documents + tree_seed_result.fetch(:removed_documents)),
			seed_changed: tree_seed_result.fetch(:seed_changed)
		}
	end

	# Removes documents from the normal seed, persisted overlay, and active set.
	def remove_from_normal_side!(normal_seed:, persisted_links:, current_active_document_ids:, documents:)
		documents = unique_documents(documents)
		return if documents.empty?

		normal_seed.remove_documents!(documents)
		persisted_links.remove_documents!(documents)
		documents.each do |document|
			current_active_document_ids.delete(document.object_id)
		end
	end

	# Returns true when tree-seed changes should schedule another outer round.
	#
	# Tree resolvers do not yet exist, so tree pruning can settle and flow
	# directly into the same round's normal phase. When tree resolvers are added
	# later, changing the seed here should trigger another full outer rebuild.
	def tree_seed_changes_require_iteration?(tree_seed_update)
		return false unless tree_seed_update.fetch(:seed_changed)

		false
	end

	# Groups removed documents by collection label for summary logging.
	def removed_documents_by_collection(documents)
		Array(documents).each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |document, grouped_documents|
			grouped_documents[document.collection.label] << document
		end
	end

	# Records one or more removed documents without double-counting them later.
	def register_removed_documents!(removed_documents:, documents:)
		Array(documents).each do |document|
			removed_documents[document.object_id] ||= document
		end
	end

	# Returns one document array with later duplicates removed by object id.
	def unique_documents(documents)
		Array(documents).each_with_object({}) do |document, unique_documents|
			unique_documents[document.object_id] ||= document
		end.values
	end

	# Logs the configured relationship summary for the final active graph.
	def log_relationship_summary(session:, normal_graph:, tree_graph:)
		tree_graph_view = Pruning::TreePhase::TreeGraphView.new(tree_graph: tree_graph)
		grouped_relationships = @configuration.configured_relationships.group_by(&:from_collection)
		entries = grouped_relationships.keys.sort.map do |from_collection|
			members = grouped_relationships.fetch(from_collection).sort_by(&:sequence)
			source_documents = {}
			target_documents = {}

			session.documents_for(from_collection).each do |document|
				member_neighbours = members.each_with_object({}) do |member, neighbours|
					graph = member.normal? ? normal_graph : tree_graph_view
					member.neighbour_documents(
						graph: graph,
						document: document,
						inverse: false
					).each do |neighbour|
						neighbours[neighbour.object_id] ||= neighbour
					end
				end
				next if member_neighbours.empty?

				source_documents[document.object_id] = document
				member_neighbours.each do |document_id, target_document|
					target_documents[document_id] ||= target_document
				end
			end

			{
				label: from_collection,
				details: "→ #{members.map(&:to_collection).uniq.join(', ')} (#{source_documents.length} linked to #{target_documents.length})"
			}
		end
		@run_logger.relationship_summary(
			entries: entries,
			relationship_count: @configuration.configured_relationships.length
		)
	end

	# Removes every inactive document from its site collection after write-back.
	def remove_inactive_documents!(active_document_ids:)
		active_document_lookup = active_document_ids.each_with_object({}) do |document_id, active_ids|
			active_ids[document_id] = true
		end
		@configuration.collections.each do |collection|
			site_collection = @site.collections[collection]
			next unless site_collection

			site_collection.docs.select! do |document|
				active_document_lookup.key?(document.object_id)
			end
		end
	end
end

end

end
end
