# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

class Engine

	# Tracks the mutable link set for one document and concrete relationship.
	#
	# Each state is resolved at most once and forms the unit of recursive
	# dependency tracking for normal relationship resolution.
	class RelationshipState
		attr_reader :document, :definition

		# Builds one new state for one document-to-collection pair.
		def initialize(engine:, document:, definition:)
			@engine = engine
			@document = document
			@definition = definition
			@status = :unseen
			@seeded = false
			@links = Jekyll::Plugins::Relationships::References::Accumulator.new(
				reference_template: @engine.configuration.reference_template,
				multiple_settings: @engine.configuration.multiple_settings
			)
		end

		# Returns true while the state is actively being resolved.
		def resolving?
			@status == :resolving
		end

		# Returns true after the state has fully resolved.
		def resolved?
			@status == :resolved
		end

		# Seeds the state from the normal seed graph once, without running resolvers.
		def ensure_seeded!
			seed_initial_links!
		end

		# Returns true when one document is active in this session.
		def active_document?(document = @document)
			@engine.active_document?(document)
		end

		# Resolves the state unless it has already been handled.
		def resolve!
			return if resolved?
			raise ResolutionError, "Cyclic relationship resolution detected while resolving #{description}." if resolving?

			@status = :resolving
			debug('resolution', 'resolve_start', {
				input_paths: @definition.foreign_paths,
				output_path: @definition.final_output_path,
				reads_frontmatter: @definition.reads_frontmatter,
				bidirectional: @definition.bidirectional,
				resolvers: @definition.resolver_classes.map { |resolver_class| @engine.debug_logger.resolver_name(resolver_class) }
			})
			ensure_seeded!
			run_resolvers!
			@engine.reapply_persisted_links(state: self)
			@engine.refresh_persisted_positions(state: self)
			@status = :resolved
			debug('resolution', 'resolve_finish', {
				references: current_references
			})
		end

		# Adds one link to the state and mirrors it when required.
		def link(reference, metadata: nil, count: 1, reflect: true, origin: 'resolver', persist: false)
			target_document = @engine.resolve_reference_document(
				reference,
				primary_path: @definition.primary_path,
				collection_hint: @definition.to_collection
			)
			unless @engine.active_document?(target_document)
				debug('mutations', 'link', {
					action: :inactive,
					origin: origin,
					target: target_document,
					target_key: @engine.registry.key_for(target_document, primary_path: @definition.primary_path),
					count: count,
					metadata: sanitised_metadata(metadata)
				})
				return {
					action: :inactive,
					entry: nil,
					target_document: target_document
				}
			end
			unless target_document.collection.label == @definition.to_collection
				raise ResolutionError, "Resolver attempted to link `#{target_document.relative_path}` outside the allowed target collection `#{@definition.to_collection}`."
			end

			result = @links.add_detailed_result(
				document: target_document,
				key: @engine.registry.key_for(target_document, primary_path: @definition.primary_path),
				metadata: sanitised_metadata(metadata),
				count: count
			)
			debug('mutations', 'link', {
				action: result.fetch(:action),
				origin: origin,
				target: target_document,
				target_key: @engine.registry.key_for(target_document, primary_path: @definition.primary_path),
				count: count,
				metadata: sanitised_metadata(metadata)
			})
			if persist && result.fetch(:action) != :ignored
				@engine.persist_link(
					source_state: self,
					target_document: target_document,
					metadata: metadata,
					count: count
				)
			end
			if reflect && @definition.bidirectional && result.fetch(:action) != :ignored
				@engine.mirror_add(source_state: self, target_document: target_document, metadata: metadata, count: count)
			end

			result.merge(target_document: target_document)
		end

		# Removes one link, or every link when no reference is given.
		def unlink(reference = nil, reflect: true, origin: 'resolver', clear_persisted: true)
			if reference.nil?
				@engine.clear_all_persisted_links(source_state: self) if clear_persisted
				if current_link_entries.empty?
					debug('mutations', 'unlink_all', {
						action: :missing,
						origin: origin
					})
				end

				current_link_entries.each do |entry|
					remove_document(document: entry.fetch(:document), reflect: reflect, origin: origin)
				end
				return
			end

			target_document = @engine.resolve_reference_document(
				reference,
				primary_path: @definition.primary_path,
				collection_hint: @definition.to_collection
			)
			@engine.clear_persisted_link(source_state: self, target_document: target_document) if clear_persisted
			remove_document(document: target_document, reflect: reflect, origin: origin)
		end

		# Returns the current resolved reference hashes after final sorting.
		def current_references
			@links.references
		end

		# Returns the current accumulated link entries in encounter order.
		def current_link_entries
			@links.encounter_entries
		end

		# Repositions reinserted persisted entries after they have been added.
		def reposition_entries!(reinsertions:, base_count:)
			@links.reposition_entries!(reinsertions: reinsertions, base_count: base_count)
		end

		private

		# Seeds the state from the source-derived normal seed graph.
		def seed_initial_links!
			return if @seeded

			@engine.seed_entries_for(@document, @definition.to_collection).each do |entry|
				link(
					entry.fetch(:document),
					metadata: entry.fetch(:metadata),
					count: entry.fetch(:count),
					reflect: false,
					origin: 'seed graph',
					persist: false
				)
			end
			@seeded = true
		end

		# Instantiates and runs every configured resolver class.
		def run_resolvers!
			@definition.resolver_classes.each do |resolver_class|
				debug('resolvers', 'resolver_start', {
					resolver: @engine.debug_logger.resolver_name(resolver_class)
				})
				resolver_class.new(engine: @engine, state: self).resolve
				debug('resolvers', 'resolver_finish', {
					resolver: @engine.debug_logger.resolver_name(resolver_class),
					references: current_references
				})
			end
		end

		# Removes one stored document and mirrors the removal if needed.
		def remove_document(document:, reflect:, origin:)
			action = @links.remove_result(document: document)
			debug('mutations', 'unlink', {
				action: action,
				origin: origin,
				target: document,
				target_key: @engine.registry.key_for(document, primary_path: @definition.primary_path)
			})
			return unless action == :removed
			return unless reflect && @definition.bidirectional

			@engine.mirror_remove(source_state: self, target_document: document)
		end

		# Removes engine-reserved properties from resolver metadata.
		def sanitised_metadata(metadata)
			return {} unless metadata.is_a?(Hash)

			metadata.each_with_object({}) do |(property, value), filtered|
				string_property = property.to_s
				next if @engine.configuration.reference_template.reserved_properties.include?(string_property)

				filtered[string_property] = value
			end
		end

		# Builds a readable state label for cycle errors.
		def description
			"`#{@document.relative_path}` (#{@definition.from_collection} -> #{@definition.to_collection})"
		end

		# Emits one debug event for this state when the definition enables it.
		def debug(area, event, details)
			@engine.debug_logger.relationship_event(
				document: @document,
				definition: @definition,
				area: area,
				event: event,
				details: details
			)
		end
	end
end

end

end
end
