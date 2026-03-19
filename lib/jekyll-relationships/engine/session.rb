# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

class Engine

	# Owns one round of relationship resolution for one active document set.
	#
	# The main engine creates a fresh session for each rebuild round so raw-path
	# caches, resolver state, and relationship accumulators never outlive the
	# graph they were built against.
	class Session
		attr_reader :site, :configuration, :registry, :tree_graph, :data_path, :debug_logger

		# Builds one new resolution session.
		def initialize(engine:, active_document_ids:, tree_graph:)
			@engine = engine
			@site = engine.site
			@configuration = engine.configuration
			@registry = engine.registry
			@tree_graph = tree_graph
			@data_path = engine.data_path
			@debug_logger = engine.debug_logger
			@active_document_ids = active_document_ids.each_with_object({}) do |document_id, active_ids|
				active_ids[document_id] = true
			end
			@string_array = Jekyll::Plugins::Relationships::Support::StringArray.new
			@raw_path_states = {}
			@relationship_states = {}
			@document_resolution_states = {}
		end

		# Returns true when the document is active in this session.
		def active_document?(document)
			@active_document_ids.key?(document.object_id)
		end

		# Returns every active document for one collection.
		def documents_for(collection)
			@registry.documents_for(collection).select do |document|
				active_document?(document)
			end
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

		# Resolves and returns one relationship array for an active document.
		def resolve_relationships(document, to_collection)
			return [] unless active_document?(document)

			state = relationship_state(document, to_collection)
			unless state
				raise ResolutionError, "No relationship is defined from collection `#{document.collection.label}` to `#{to_collection}`."
			end

			resolve_state(state)
			state.current_references
		end

		# Resolves every outgoing pair for one active document.
		def resolve_document(document)
			return document unless active_document?(document)
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

		# Resolves one helper or resolver reference to a document, even if inactive.
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
			return unless active_document?(target_document)

			mirror_state = relationship_state(target_document, source_state.definition.from_collection)
			return unless mirror_state

			mirror_state.link(
				source_state.document,
				metadata: metadata,
				count: count,
				reflect: false,
				origin: "mirror #{source_state.document.relative_path}"
			)
		end

		# Mirrors one bidirectional removal into the reverse state.
		def mirror_remove(source_state:, target_document:)
			return unless active_document?(target_document)

			mirror_state = relationship_state(target_document, source_state.definition.from_collection)
			return unless mirror_state

			mirror_state.unlink(
				source_state.document,
				reflect: false,
				origin: "mirror #{source_state.document.relative_path}"
			)
		end

		# Returns the cached relationship state for one concrete pair.
		def relationship_state(document, to_collection)
			return nil unless active_document?(document)

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

		# Resolves every configured normal relationship state once.
		def resolve_all_relationships!
			@configuration.collections.each do |collection|
				definitions = @configuration.normal_relationships_for(collection)
				next if definitions.empty?

				documents_for(collection).each do |document|
					definitions.each do |definition|
						resolve_relationships(document, definition.to_collection)
					end
				end
			end
		end

		# Writes the current session's resolved relationships back to frontmatter.
		def write_back!
			WriteBack.new(engine: self).write_normal_relationships!
		end

		private

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
end
