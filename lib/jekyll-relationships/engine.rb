# frozen_string_literal: true

require 'jekyll-relationships/engine/session'
require 'jekyll-relationships/engine/raw_path_state'
require 'jekyll-relationships/engine/relationship_state'
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

		@debug_logger = DebugLogger.new
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
		original_tree_graph = build_tree_graph(active_document_ids: all_active_document_ids)
		tree_provenance = Pruning::TreeProvenance.new(tree_graph: original_tree_graph)
		prune_result = prune_result_for(
			tree_provenance: tree_provenance,
			original_tree_graph: original_tree_graph
		)
		final_session = Session.new(
			engine: self,
			active_document_ids: prune_result.fetch(:active_document_ids),
			tree_graph: prune_result.fetch(:tree_graph)
		)
		final_session.resolve_all_relationships!
		final_normal_graph = Pruning::NormalGraph.new(session: final_session)

		log_relationship_summary(
			session: final_session,
			normal_graph: final_normal_graph,
			tree_graph: prune_result.fetch(:tree_graph)
		)
		@run_logger.pruning_summary(
			removed_documents_by_collection: removed_documents_by_collection(prune_result.fetch(:removed_documents))
		) if @configuration.pruning_enabled?

		final_session.write_back!
		prune_result.fetch(:tree_graph).write_back!
		remove_inactive_documents!(active_document_ids: prune_result.fetch(:active_document_ids))
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

	# Runs the configured prune rounds and returns the final active document set.
	def prune_result_for(tree_provenance:, original_tree_graph:)
		current_active_document_ids = all_active_document_ids
		removed_documents = {}
		current_tree_graph = original_tree_graph
		return {
			active_document_ids: current_active_document_ids,
			removed_documents: [],
			tree_graph: current_tree_graph
		} unless @configuration.pruning_enabled?

		tree_phase = Pruning::TreePhase.new(engine: self, provenance: tree_provenance)
		@configuration.prune_settings.prune_rounds.times do
			tree_phase_result = tree_phase.process(active_document_ids: current_active_document_ids)
			register_removed_documents!(
				removed_documents: removed_documents,
				documents: tree_phase_result.fetch(:removed_documents)
			)
			current_active_document_ids = tree_phase_result.fetch(:active_document_ids)
			current_tree_graph = tree_phase_result.fetch(:tree_graph)

			session = Session.new(
				engine: self,
				active_document_ids: current_active_document_ids,
				tree_graph: current_tree_graph
			)
			session.resolve_all_relationships!

			normal_removed_documents = Pruning::RulePruner.new(
				graph: Pruning::NormalGraph.new(session: session),
				rules: @configuration.normal_prune_rules
			).prune!
			if normal_removed_documents.empty?
				return {
					active_document_ids: current_active_document_ids,
					removed_documents: removed_documents.values,
					tree_graph: current_tree_graph
				}
			end

			register_removed_documents!(
				removed_documents: removed_documents,
				documents: normal_removed_documents
			)
			current_active_document_ids -= normal_removed_documents.map(&:object_id)
			post_normal_tree_phase = tree_phase.process(active_document_ids: current_active_document_ids)
			register_removed_documents!(
				removed_documents: removed_documents,
				documents: post_normal_tree_phase.fetch(:removed_documents)
			)
			current_active_document_ids = post_normal_tree_phase.fetch(:active_document_ids)
			current_tree_graph = post_normal_tree_phase.fetch(:tree_graph)
		end

		{
			active_document_ids: current_active_document_ids,
			removed_documents: removed_documents.values,
			tree_graph: current_tree_graph
		}
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

	# Logs the configured relationship summary for the final active graph.
	def log_relationship_summary(session:, normal_graph:, tree_graph:)
		tree_graph_view = Pruning::TreePhase::TreeGraphView.new(tree_graph: tree_graph)
		grouped_relationships = @configuration.configured_relationships.group_by(&:from_collection)
		lines = grouped_relationships.keys.sort.map do |from_collection|
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

			"#{from_collection} → #{members.map(&:to_collection).uniq.join(', ')} (#{source_documents.length} linked to #{target_documents.length})"
		end
		@run_logger.relationship_summary(
			lines: lines,
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
