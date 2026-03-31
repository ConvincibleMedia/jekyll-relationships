# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

class Engine

	# Stores the source-derived normal relationship graph used to seed each round.
	#
	# The seed graph is built once from frontmatter, including deterministic
	# bidirectional mirrors, and is later reduced only by document removals.
	# Resolver output never flows back into this structure.
	class NormalSeed
		# Builds one normal seed graph for the current active document set.
		def initialize(engine:, active_document_ids:)
			@engine = engine
			@configuration = engine.configuration
			@registry = engine.registry
			@data_path = engine.data_path
			@debug_logger = engine.debug_logger
			@active_document_ids = active_document_ids.each_with_object({}) do |document_id, active_ids|
				active_ids[document_id] = true
			end
			@string_array = Jekyll::Plugins::Relationships::Support::StringArray.new
			@raw_path_states = {}
			@entries_by_state = {}
			build!
		end

		# Returns the seed entries for one concrete document-to-collection pair.
		def entries_for(document, to_collection)
			duplicate_entries(@entries_by_state[[document.object_id, to_collection]])
		end

		# Permanently removes documents from the seed graph in both source and target positions.
		def remove_documents!(documents)
			removed_document_ids = Array(documents).each_with_object({}) do |document, lookup|
				lookup[document.object_id] = true
			end
			return if removed_document_ids.empty?

			@entries_by_state.delete_if do |(source_document_id, _to_collection), _entries|
				removed_document_ids.key?(source_document_id)
			end
			@entries_by_state.each_value do |entries|
				entries.reject! do |entry|
					removed_document_ids.key?(entry.fetch(:document).object_id)
				end
			end
		end

		private

		# Builds the full source-derived seed graph once.
		def build!
			accumulators = {}

			@configuration.collections.each do |collection|
				@configuration.normal_relationships_for(collection).each do |definition|
					next unless definition.reads_frontmatter

					documents_for(collection).each do |document|
						seed_definition_from_frontmatter(
							accumulators: accumulators,
							document: document,
							definition: definition
						)
					end
				end
			end

			@entries_by_state = accumulators.each_with_object({}) do |(state_key, accumulator), entries_by_state|
				entries_by_state[state_key] = accumulator.encounter_entries
			end
		end

		# Reads and stores one concrete direct relationship definition from frontmatter.
		def seed_definition_from_frontmatter(accumulators:, document:, definition:)
			definition.foreign_paths.each do |path|
				raw_state = raw_path_state(document, path)
				debug_relationship_event(
					document: document,
					definition: definition,
					event: 'raw_path',
					details: {
						path: path,
						present: raw_state.present?,
						value: raw_state.raw_value
					}
				)
				next unless raw_state.present?

				resolved_entries = raw_state.resolved_entries_for(
					primary_path: definition.primary_path,
					registry: @registry,
					active_document_checker: proc { |resolved_document| active_document?(resolved_document) }
				)
				debug_relationship_event(
					document: document,
					definition: definition,
					event: 'raw_path_resolved',
					details: {
						path: path,
						entries: resolved_entries.compact
					}
				)

				resolved_entries.each do |entry|
					next unless entry
					if entry.fetch(:document).collection.label != definition.to_collection
						debug_relationship_event(
							document: document,
							definition: definition,
							event: 'raw_path_skipped',
							details: {
								path: path,
								target: entry.fetch(:document),
								target_key: entry.fetch(:key),
								actual_collection: entry.fetch(:document).collection.label,
								expected_collection: definition.to_collection
							}
						)
						next
					end

					add_direct_entry(
						accumulators: accumulators,
						document: document,
						definition: definition,
						entry: entry
					)
				end
			end
		end

		# Adds one direct link and its deterministic bidirectional mirror when configured.
		def add_direct_entry(accumulators:, document:, definition:, entry:)
			accumulator_for(
				accumulators: accumulators,
				document: document,
				to_collection: definition.to_collection
			).add(
				document: entry.fetch(:document),
				key: entry.fetch(:key),
				metadata: entry.fetch(:metadata),
				count: entry.fetch(:count)
			)

			return unless definition.bidirectional

			accumulator_for(
				accumulators: accumulators,
				document: entry.fetch(:document),
				to_collection: definition.from_collection
			).add(
				document: document,
				key: @registry.key_for(document, primary_path: definition.primary_path),
				metadata: entry.fetch(:metadata),
				count: entry.fetch(:count)
			)
		end

		# Returns one reusable accumulator for one concrete source pair.
		def accumulator_for(accumulators:, document:, to_collection:)
			accumulators[[document.object_id, to_collection]] ||= Jekyll::Plugins::Relationships::References::Accumulator.new(
				reference_template: @configuration.reference_template,
				multiple_settings: @configuration.multiple_settings
			)
		end

		# Returns every active document for one collection.
		def documents_for(collection)
			@registry.documents_for(collection).select do |document|
				active_document?(document)
			end
		end

		# Returns true when one document is still active in the seed graph.
		def active_document?(document)
			@active_document_ids.key?(document.object_id)
		end

		# Returns the cached raw-path parser for one document/path pair.
		def raw_path_state(document, path)
			@raw_path_states[[document.object_id, path]] ||= RawPathState.new(
				document: document,
				path: path,
				data_path: @data_path,
				string_array: @string_array,
				reference_template: @configuration.reference_template
			)
		end

		# Duplicates one stored seed-entry array defensively.
		def duplicate_entries(entries)
			Array(entries).map(&:dup)
		end

		# Emits one debug event while the seed graph is being built.
		def debug_relationship_event(document:, definition:, event:, details:)
			@debug_logger.relationship_event(
				document: document,
				definition: definition,
				area: 'upgrading',
				event: event,
				details: details
			)
		end
	end
end

end

end
end
