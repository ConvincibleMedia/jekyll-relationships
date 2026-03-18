# frozen_string_literal: true

require 'jekyll-relationships/engine/raw_path_state'
require 'jekyll-relationships/engine/relationship_state'
require 'jekyll-relationships/engine/write_back'
require 'jekyll-relationships/trees/graph'

module Jekyll
module Plugins

module Relationships

# Orchestrates configuration parsing, resolution, and final write-back.
#
# One engine instance handles one Jekyll build and owns the mutable runtime
# state used while relationships are resolved recursively.
class Engine
	attr_reader :site, :configuration, :registry, :tree_graph, :data_path

	# Builds one engine for one Jekyll site build.
	def initialize(site:)
		@site = site
		@configuration = Configuration.new(@site.config)
		@registry = Documents::Registry.new(site: @site, collections: @configuration.collections)
		@data_path = Jekyll::Plugins::Relationships::Support::DataPath.new
		@string_array = Jekyll::Plugins::Relationships::Support::StringArray.new
		@tree_graph = Trees::Graph.new(
			site: @site,
			configuration: @configuration,
			registry: @registry,
			data_path: @data_path
		)
		@write_back = WriteBack.new(engine: self)
		@raw_path_states = {}
		@relationship_states = {}
		@document_resolution_states = {}
	end

	# Processes the whole site.
	def process!
		return if @configuration.collections.empty?

		@registry.validate_collections!
		@registry.validate_primary_paths!(primary_paths: @configuration.primary_paths)
		@tree_graph.build!
		resolve_all_relationships!
		@write_back.write_normal_relationships!
		@tree_graph.write_back!
	end

	# Returns the cached raw-path state for one document and path.
	def raw_path_state(document, path)
		@raw_path_states[[document.object_id, path]] ||= RawPathState.new(
			document: document,
			path: path,
			data_path: @data_path,
			string_array: @string_array,
			reference_template: @configuration.reference_template,
			multiple_settings: @configuration.multiple_settings
		)
	end

	# Resolves and returns one relationship array.
	def resolve_relationships(document, to_collection)
		state = relationship_state(document, to_collection)
		unless state
			raise ResolutionError, "No relationship is defined from collection `#{document.collection.label}` to `#{to_collection}`."
		end

		resolve_state(state)
		state.current_references
	end

	# Resolves every outgoing pair for one document.
	def resolve_document(document)
		return document unless @registry.participating?(document)

		document_id = document.object_id
		status = @document_resolution_states[document_id]
		raise ResolutionError, "Cyclic document resolution detected for `#{document.relative_path}`." if status == :resolving
		return document if status == :resolved

		@document_resolution_states[document_id] = :resolving
		@configuration.normal_relationships_for(document.collection.label).each do |definition|
			resolve_relationships(document, definition.to_collection)
		end
		@document_resolution_states[document_id] = :resolved
		document
	end

	# Resolves one helper or resolver reference to a document.
	def resolve_reference_document(reference, primary_path:, collection_hint: nil)
		return reference if reference.is_a?(Jekyll::Document)

		parsed_reference = @configuration.reference_template.parse(reference)
		return parsed_reference.page if parsed_reference.document?

		@registry.lookup(
			key: parsed_reference.key,
			primary_path: primary_path,
			collection: collection_hint || (parsed_reference.collection.nil? ? nil : parsed_reference.collection.to_s)
		)
	end

	# Mirrors one bidirectional add into the reverse state.
	def mirror_add(source_state:, target_document:, metadata:, count:)
		mirror_state = relationship_state(target_document, source_state.definition.from_collection)
		return unless mirror_state

		mirror_state.link(source_state.document, metadata: metadata, count: count, reflect: false)
	end

	# Mirrors one bidirectional removal into the reverse state.
	def mirror_remove(source_state:, target_document:)
		mirror_state = relationship_state(target_document, source_state.definition.from_collection)
		return unless mirror_state

		mirror_state.unlink(source_state.document, reflect: false)
	end

	# Returns the cached relationship state for one concrete pair.
	def relationship_state(document, to_collection)
		definition = @configuration.normal_relationship_for(
			from_collection: document.collection.label,
			to_collection: to_collection
		)
		return nil unless definition

		@relationship_states[[document.object_id, to_collection]] ||= RelationshipState.new(
			engine: self,
			document: document,
			definition: definition
		)
	end

	private

	# Resolves every configured normal relationship state once.
	def resolve_all_relationships!
		@configuration.collections.each do |collection|
			definitions = @configuration.normal_relationships_for(collection)
			next if definitions.empty?

			@registry.documents_for(collection).each do |document|
				definitions.each do |definition|
					resolve_relationships(document, definition.to_collection)
				end
			end
		end
	end

	# Resolves one relationship state with cycle detection.
	def resolve_state(state)
		return state if state.resolved?
		raise ResolutionError, "Cyclic relationship resolution detected while resolving `#{state.document.relative_path}`." if state.resolving?

		state.resolve!
		state
	end
end

end

end
end
