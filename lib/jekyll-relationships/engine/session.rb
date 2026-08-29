# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

class Engine

	# Owns one round of relationship resolution for one active document set.
	#
	# The main engine creates a fresh session for each rebuild round so raw-path
	# caches, resolver state, and relationship accumulators never outlive the
	# graph they were built against. Every round reseeds from the current source
	# graph plus any explicit persisted-link overlay.
	class Session
		attr_reader :site, :configuration, :registry, :tree_graph, :data_path, :debug_logger

		# Builds one new resolution session.
		def initialize(engine:, active_document_ids:, tree_graph:, normal_seed:, persisted_links:)
			@engine = engine
			@site = engine.site
			@configuration = engine.configuration
			@registry = engine.registry
			@tree_graph = tree_graph
			@data_path = engine.data_path
			@debug_logger = engine.debug_logger
			@normal_seed = normal_seed
			@persisted_links = persisted_links
			@persisted_links.start_round!
			@active_document_ids = active_document_ids.each_with_object({}) do |document_id, active_ids|
				active_ids[document_id] = true
			end
			@string_array = Jekyll::Plugins::Relationships::Support::StringArray.new
			@raw_path_states = {}
			@relationship_states = {}
			@document_resolution_states = {}
			@initial_links_seeded = false
			@defer_bidirectional_mirror_resolvers = false
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
				reference_template: @configuration.reference_template
			)
		end

		# Resolves and returns one relationship array for an active document.
		def resolve_relationships(document, to_collection)
			return [] unless active_document?(document)

			state = relationship_state(document, to_collection)
			unless state
				raise ResolutionError, "No relationship is defined from collection `#{document.collection.label}` to `#{to_collection}`."
			end

			ensure_initial_links_seeded!
			return state.current_references if defer_bidirectional_mirror_resolver_for?(state)

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
		def resolve_reference_document(reference, primary_path:, scope_fields: [], referring_document: nil, relationship: nil, collection_hint: nil)
			if reference.is_a?(Jekyll::Document)
				@registry.scope_for(reference, scope_fields: scope_fields, relationship: relationship)
				return reference
			end

			parsed_reference = @configuration.reference_template.parse(
				reference,
				context: reference_context(relationship: relationship, document: referring_document)
			)
			effective_scope = @registry.effective_scope_for(
				reference_scope: parsed_reference.scope,
				referring_document: referring_document,
				scope_fields: scope_fields,
				relationship: relationship
			)
			if parsed_reference.document?
				@registry.validate_scope_match!(
					document: parsed_reference.page,
					scope: effective_scope,
					scope_fields: scope_fields,
					relationship: relationship,
					referring_document: referring_document
				)
				return parsed_reference.page
			end

			@registry.lookup(
				key: parsed_reference.key,
				primary_path: primary_path,
				collection: collection_hint || (parsed_reference.collection.nil? ? nil : parsed_reference.collection.to_s),
				scope_fields: scope_fields,
				scope: effective_scope,
				relationship: relationship,
				referring_document: referring_document
			)
		end

		# Returns the source-derived seed entries for one concrete pair.
		def seed_entries_for(document, to_collection)
			return [] unless active_document?(document)

			@normal_seed.entries_for(document, to_collection).select do |entry|
				active_document?(entry.fetch(:document))
			end
		end

		# Records one persisted resolver link so it can survive later rounds.
		def persist_link(source_state:, target_document:, metadata:, count:)
			@persisted_links.persist_link(
				source_state: source_state,
				target_document: target_document,
				metadata: metadata,
				count: count
			)
		end

		# Removes one persisted resolver link.
		def clear_persisted_link(source_state:, target_document:)
			@persisted_links.clear_link(
				source_state: source_state,
				target_document: target_document
			)
		end

		# Removes every persisted resolver link on one state.
		def clear_all_persisted_links(source_state:)
			@persisted_links.clear_all(source_state: source_state)
		end

		# Reapplies persisted links only when resolvers did not recreate them.
		def reapply_persisted_links(state:)
			@persisted_links.reapply_missing_links(state: state)
		end

		# Refreshes remembered persisted-link positions from the final current ordering.
		def refresh_persisted_positions(state:)
			@persisted_links.refresh_positions(state: state)
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
			@defer_bidirectional_mirror_resolvers = true
			resolve_all_relationships_pass!
			@defer_bidirectional_mirror_resolvers = false
			resolve_deferred_bidirectional_mirror_resolvers!
		ensure
			@defer_bidirectional_mirror_resolvers = false
		end

		# Writes the current session's resolved relationships back to frontmatter.
		def write_back!
			WriteBack.new(engine: self).write_normal_relationships!
		end

		private

		# Builds consistent relationship and source-document details for reference parsing errors.
		def reference_context(relationship:, document:)
			parts = []
			parts << "Relationship `#{relationship}`" unless relationship.nil? || relationship.to_s.empty?
			parts << "reference on document `#{document.relative_path}`" if document
			parts.join(' ')
		end

		# Seeds every normal relationship state before any resolver mutates the graph.
		#
		# Bidirectional removals can target reverse states that have not been
		# resolved yet. Seeding the whole current graph up front ensures those
		# reverse states already contain their direct seed links before any resolver
		# adds or removes mirrored relationships.
		def ensure_initial_links_seeded!
			return if @initial_links_seeded

			@configuration.collections.each do |collection|
				@configuration.normal_relationships_for(collection).each do |definition|
					documents_for(collection).each do |document|
						relationship_state(document, definition.to_collection)&.ensure_seeded!
					end
				end
			end
			@initial_links_seeded = true
		end

		# Resolves one relationship state with cycle detection.
		def resolve_state(state)
			return state if state.resolved?
			raise ResolutionError, "Cyclic relationship resolution detected while resolving `#{state.document.relative_path}`." if state.resolving?

			state.resolve!
			state
		end

		# Resolves every configured normal relationship state in collection and sequence order.
		def resolve_all_relationships_pass!
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

		# Runs deferred resolvers for inverse bidirectional mirrors after forward resolution settles.
		def resolve_deferred_bidirectional_mirror_resolvers!
			@configuration.collections.each do |collection|
				definitions = @configuration.normal_relationships_for(collection).select do |definition|
					deferred_bidirectional_mirror_definition?(definition)
				end
				next if definitions.empty?

				documents_for(collection).each do |document|
					definitions.each do |definition|
						resolve_relationships(document, definition.to_collection)
					end
				end
			end
		end

		# Returns true when one definition should run in the deferred mirror-resolver pass.
		def deferred_bidirectional_mirror_definition?(definition)
			definition.bidirectional_mirror? && !definition.resolver_classes.empty?
		end

		# Returns true when this state should expose current links now but defer running its resolver.
		def defer_bidirectional_mirror_resolver_for?(state)
			return false unless @defer_bidirectional_mirror_resolvers

			deferred_bidirectional_mirror_definition?(state.definition)
		end
	end
end

end

end
end
