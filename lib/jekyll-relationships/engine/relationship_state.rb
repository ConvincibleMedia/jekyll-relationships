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
			@raw_seeded = false
			@links_by_document_id = {}
			@link_order = []
		end

		# Returns true while the state is actively being resolved.
		def resolving?
			@status == :resolving
		end

		# Returns true after the state has fully resolved.
		def resolved?
			@status == :resolved
		end

		# Resolves the state unless it has already been handled.
		def resolve!
			return if resolved?
			raise ResolutionError, "Cyclic relationship resolution detected while resolving #{description}." if resolving?

			@status = :resolving
			seed_raw_links!
			run_resolvers!
			@status = :resolved
		end

		# Adds one link to the state and mirrors it when required.
		def link(reference, metadata: nil, reflect: true)
			target_document = @engine.resolve_reference_document(
				reference,
				primary_path: @definition.primary_path,
				collection_hint: @definition.to_collection
			)
			unless target_document.collection.label == @definition.to_collection
				raise ResolutionError, "Resolver attempted to link `#{target_document.relative_path}` outside the allowed target collection `#{@definition.to_collection}`."
			end

			document_id = target_document.object_id
			return if @links_by_document_id.key?(document_id)

			@links_by_document_id[document_id] = {
				document: target_document,
				metadata: sanitised_metadata(metadata)
			}
			@link_order << document_id

			return unless reflect && @definition.bidirectional

			@engine.mirror_add(source_state: self, target_document: target_document, metadata: metadata)
		end

		# Removes one link, or every link when no reference is given.
		def unlink(reference = nil, reflect: true)
			if reference.nil?
				@link_order.dup.each do |document_id|
					remove_document_id(document_id: document_id, reflect: reflect)
				end
				return
			end

			target_document = @engine.resolve_reference_document(
				reference,
				primary_path: @definition.primary_path,
				collection_hint: @definition.to_collection
			)
			remove_document_id(document_id: target_document.object_id, reflect: reflect)
		end

		# Returns the current resolved reference hashes.
		def current_references
			current_link_payloads.map { |payload| payload.fetch(:reference) }
		end

		# Returns the current link payloads including their target documents.
		def current_link_payloads
			@link_order.each_with_object([]) do |document_id, payloads|
				entry = @links_by_document_id[document_id]
				next unless entry

				target_document = entry.fetch(:document)
				payloads << {
					document: target_document,
					reference: @engine.configuration.reference_template.build(
						document: target_document,
						key: @engine.registry.key_for(target_document, primary_path: @definition.primary_path),
						metadata: entry.fetch(:metadata)
					)
				}
			end
		end

		private

		# Seeds the state from raw frontmatter once.
		def seed_raw_links!
			return unless @definition.reads_frontmatter
			return if @raw_seeded

			@definition.foreign_paths.each do |path|
				raw_state = @engine.raw_path_state(@document, path)
				next unless raw_state.present?

				raw_state.resolved_entries_for(primary_path: @definition.primary_path, registry: @engine.registry).each do |entry|
					next unless entry
					next unless entry.fetch(:document).collection.label == @definition.to_collection

					link(entry.fetch(:document), metadata: entry.fetch(:metadata), reflect: @definition.bidirectional)
				end
			end

			@raw_seeded = true
		end

		# Instantiates and runs every configured resolver class.
		def run_resolvers!
			@definition.resolver_classes.each do |resolver_class|
				resolver_class.new(engine: @engine, state: self).resolve
			end
		end

		# Removes one stored document id and mirrors the removal if needed.
		def remove_document_id(document_id:, reflect:)
			entry = @links_by_document_id.delete(document_id)
			return unless entry

			@link_order.delete(document_id)
			return unless reflect && @definition.bidirectional

			@engine.mirror_remove(source_state: self, target_document: entry.fetch(:document))
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
	end
end

end

end
end
