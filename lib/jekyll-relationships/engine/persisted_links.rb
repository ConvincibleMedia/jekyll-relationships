# frozen_string_literal: true

require 'json'

module Jekyll
module Plugins

module Relationships

class Engine

	# Stores resolver-promoted links that may be restored in later rounds.
	#
	# Persisted links are a fallback overlay, not part of the source-derived
	# seeds. A later round only reapplies them after resolvers have had their own
	# chance to recreate the same links naturally.
	class PersistedLinks
		# Builds one persisted-link store with the active duplicate-handling rules.
		def initialize(engine:)
			@engine = engine
			@configuration = engine.configuration
			@registry = engine.registry
			@entries_by_state = Hash.new { |hash, key| hash[key] = [] }
			@next_order = 0
			@round_identifier = 0
		end

		# Marks the start of one new resolution round.
		def start_round!
			@round_identifier += 1
		end

		# Records one persisted link for the given directional relationship pair.
		def persist_link(source_state:, target_document:, metadata:, count:)
			persist_directional_link(
				document: source_state.document,
				to_collection: source_state.definition.to_collection,
				target_document: target_document,
				key: @registry.key_for(target_document, primary_path: source_state.definition.primary_path),
				metadata: metadata,
				count: count
			)

			return unless source_state.definition.bidirectional

			persist_directional_link(
				document: target_document,
				to_collection: source_state.definition.from_collection,
				target_document: source_state.document,
				key: @registry.key_for(source_state.document, primary_path: source_state.definition.primary_path),
				metadata: metadata,
				count: count
			)
		end

		# Removes one persisted link from the given directional pair.
		def clear_link(source_state:, target_document:)
			clear_directional_link(
				document: source_state.document,
				to_collection: source_state.definition.to_collection,
				target_document: target_document
			)

			return unless source_state.definition.bidirectional

			clear_directional_link(
				document: target_document,
				to_collection: source_state.definition.from_collection,
				target_document: source_state.document
			)
		end

		# Removes every persisted link for the given directional pair.
		def clear_all(source_state:)
			state_entries = @entries_by_state[[source_state.document.object_id, source_state.definition.to_collection]].dup
			clear_directional_state(
				document: source_state.document,
				to_collection: source_state.definition.to_collection
			)

			return unless source_state.definition.bidirectional

			state_entries.each do |entry|
				clear_directional_link(
					document: entry.fetch(:document),
					to_collection: source_state.definition.from_collection,
					target_document: source_state.document
				)
			end
		end

		# Drops any persisted links whose source or target documents no longer survive.
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

		# Restores any still-valid persisted links that resolvers did not recreate.
		def reapply_missing_links(state:)
			state_entries = @entries_by_state[[state.document.object_id, state.definition.to_collection]]
			return if state_entries.empty?

			cleanup_dead_entries!(
				state: state,
				state_entries: state_entries
			)
			return if state_entries.empty?

			missing_entries = missing_entries_for(state_entries: state_entries, current_entries: state.current_link_entries)
			return if missing_entries.empty?

			base_count = state.current_link_entries.length
			reinsertions = []
			missing_entries.each do |entry|
				result = state.link(
					entry.fetch(:document),
					metadata: entry.fetch(:metadata),
					count: entry.fetch(:count),
					reflect: true,
					origin: 'persisted overlay',
					persist: false
				)
				next unless result.fetch(:action) == :added

				reinsertions << {
					entry: result.fetch(:entry),
					position_ratio: entry.fetch(:position_ratio),
					order: entry.fetch(:order)
				}
			end

			state.reposition_entries!(reinsertions: reinsertions, base_count: base_count) unless reinsertions.empty?
		end

		# Refreshes stored position hints from the latest resolved ordering.
		def refresh_positions(state:)
			state_entries = @entries_by_state[[state.document.object_id, state.definition.to_collection]]
			return if state_entries.empty?

			current_entries = state.current_link_entries
			return if current_entries.empty?

			if @configuration.multiple_settings.keep?
				update_keep_positions!(
					state_entries: state_entries,
					current_entries: current_entries
				)
				return
			end

			current_indexes = current_entries.each_with_index.each_with_object({}) do |(entry, index), indexes|
				indexes[entry.fetch(:document).object_id] = {
					index: index,
					entry: entry
				}
			end
			state_entries.each do |entry|
				match = current_indexes[entry.fetch(:document).object_id]
				next unless match

				entry[:position_ratio] = position_ratio(index: match.fetch(:index), length: current_entries.length)
			end
		end

		private

		# Stores one directional persisted entry under the active duplicate mode.
		def persist_directional_link(document:, to_collection:, target_document:, key:, metadata:, count:)
			state_entries = @entries_by_state[[document.object_id, to_collection]]
			if @configuration.multiple_settings.keep?
				existing_entry = state_entries.find do |entry|
					entry_signature(entry) == signature_for(document: target_document, metadata: metadata) &&
						entry.fetch(:last_seen_round) != @round_identifier
				end
				if existing_entry
					existing_entry[:last_seen_round] = @round_identifier
					return
				end

				state_entries << build_entry(
					document: target_document,
					key: key,
					metadata: metadata,
					count: 1
				)
				return
			end

			existing_entry = state_entries.find do |entry|
				entry.fetch(:document) == target_document
			end
			if existing_entry
				return if @configuration.multiple_settings.drop?

				existing_entry[:count] += normalise_count(count)
				existing_entry[:metadata] = merge_metadata_under(
					existing_metadata: existing_entry.fetch(:metadata),
					incoming_metadata: metadata
				)
				return
			end

			state_entries << build_entry(
				document: target_document,
				key: key,
				metadata: metadata,
				count: @configuration.multiple_settings.count? ? normalise_count(count) : 1
			)
		end

		# Removes one directional persisted entry.
		def clear_directional_link(document:, to_collection:, target_document:)
			state_entries = @entries_by_state[[document.object_id, to_collection]]
			state_entries.reject! do |entry|
				entry.fetch(:document) == target_document
			end
		end

		# Removes every directional persisted entry for one pair.
		def clear_directional_state(document:, to_collection:)
			@entries_by_state.delete([document.object_id, to_collection])
		end

		# Builds one new persisted entry record.
		def build_entry(document:, key:, metadata:, count:)
			entry = {
				document: document,
				key: key,
				metadata: normalise_metadata(metadata),
				count: count,
				position_ratio: nil,
				order: @next_order,
				last_seen_round: @round_identifier
			}
			@next_order += 1
			entry
		end

		# Removes dead-source or dead-target entries before reuse.
		def cleanup_dead_entries!(state:, state_entries:)
			state_entries.reject! do |entry|
				!state.active_document?(state.document) || !state.active_document?(entry.fetch(:document))
			end
		end

		# Returns the subset of persisted entries that are still missing this round.
		def missing_entries_for(state_entries:, current_entries:)
			if @configuration.multiple_settings.keep?
				return missing_keep_entries(state_entries: state_entries, current_entries: current_entries)
			end

			current_entries_by_document = current_entries.each_with_object({}) do |entry, grouped_entries|
				grouped_entries[entry.fetch(:document).object_id] = entry
			end
			state_entries.each_with_object([]) do |entry, missing_entries|
				current_entry = current_entries_by_document[entry.fetch(:document).object_id]
				if current_entry.nil?
					missing_entries << entry
					next
				end
				next unless @configuration.multiple_settings.count?
				next unless current_entry.fetch(:count) < entry.fetch(:count)

				missing_entries << entry.merge(
					count: entry.fetch(:count) - current_entry.fetch(:count)
				)
			end
		end

		# Returns the missing persisted occurrences for keep mode.
		def missing_keep_entries(state_entries:, current_entries:)
			current_counts_by_signature = current_entries.each_with_object(Hash.new(0)) do |entry, counts|
				counts[entry_signature(entry)] += 1
			end
			state_entries.each_with_object([]) do |entry, missing_entries|
				signature = entry_signature(entry)
				if current_counts_by_signature[signature].positive?
					current_counts_by_signature[signature] -= 1
					next
				end

				missing_entries << entry
			end
		end

		# Updates keep-mode persisted positions by consuming current occurrences in order.
		def update_keep_positions!(state_entries:, current_entries:)
			current_indexes_by_signature = current_entries.each_with_index.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(entry, index), indexes|
				indexes[entry_signature(entry)] << index
			end
			state_entries.each do |entry|
				indexes = current_indexes_by_signature[entry_signature(entry)]
				next if indexes.empty?

				entry[:position_ratio] = position_ratio(index: indexes.shift, length: current_entries.length)
			end
		end

		# Builds one stable signature for keep-mode matching.
		def entry_signature(entry)
			signature_for(
				document: entry.fetch(:document),
				metadata: entry.fetch(:metadata)
			)
		end

		# Builds one stable signature for one persisted keep-mode occurrence.
		def signature_for(document:, metadata:)
			[
				document.object_id,
				JSON.generate(normalise_metadata(metadata))
			]
		end

		# Converts one final list index into a proportional reinsertion hint.
		def position_ratio(index:, length:)
			return 1.0 if length <= 1

			index.to_f / (length - 1)
		end

		# Merges later metadata under the first-seen persisted metadata.
		def merge_metadata_under(existing_metadata:, incoming_metadata:)
			Jekyll::Plugins::Relationships::Support.hash_deep_merge(
				normalise_metadata(incoming_metadata),
				normalise_metadata(existing_metadata)
			)
		end

		# Normalises metadata into a string-keyed hash.
		def normalise_metadata(metadata)
			Jekyll::Plugins::Relationships::Support.stringify_hash(metadata)
		end

		# Validates and normalises an incoming counted multiplicity.
		def normalise_count(count)
			integer_count = if count.is_a?(Integer)
							 count
						 elsif count.is_a?(String) && count.strip.match?(/\A\d+\z/)
							 count.to_i
						 else
							 raise ResolutionError, "Relationship count `#{count.inspect}` must be a positive integer."
						 end
			raise ResolutionError, "Relationship count `#{count.inspect}` must be a positive integer." if integer_count < 1

			integer_count
		end
	end
end

end

end
end
