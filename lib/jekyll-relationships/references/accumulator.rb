# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships
module References

# Accumulates resolved relationship entries according to the active duplicate
# handling mode.
#
# The accumulator keeps insertion order, aggregates counts when configured to do
# so, applies metadata merge-under behaviour for counted duplicates, and owns the
# optional final sorting pass.
class Accumulator

	# Builds one accumulator for one duplicate-handling scope.
	def initialize(reference_template:, multiple_settings:)
		@reference_template = reference_template
		@multiple_settings = multiple_settings
		@entries = []
		@entries_by_document_id = {}
		@next_position = 0
	end

	# Adds one resolved relationship entry.
	def add(document:, key:, metadata: nil, count: 1)
		if @multiple_settings.keep?
			append_entry(document: document, key: key, metadata: metadata, count: 1)
			return true
		end

		existing_entry = @entries_by_document_id[document.object_id]
		if existing_entry
			return false if @multiple_settings.drop?

			existing_entry[:count] += normalise_count(count)
			existing_entry[:metadata] = merge_metadata_under(
				existing_metadata: existing_entry[:metadata],
				incoming_metadata: metadata
			)
			return true
		end

		entry = append_entry(
			document: document,
			key: key,
			metadata: metadata,
			count: counted_mode? ? normalise_count(count) : 1
		)
		@entries_by_document_id[document.object_id] = entry
		true
	end

	# Removes every stored occurrence of one target document.
	def remove(document:)
		if @multiple_settings.keep?
			removed_entries = @entries.reject! { |entry| entry.fetch(:document) == document }
			return !removed_entries.nil?
		end

		entry = @entries_by_document_id.delete(document.object_id)
		return false unless entry

		@entries.delete(entry)
		true
	end

	# Returns the accumulated entries in encounter order.
	def encounter_entries
		@entries.map { |entry| duplicate_entry(entry) }
	end

	# Returns the accumulated entries after any configured final sorting pass.
	def materialised_entries
		entries = encounter_entries
		return entries unless counted_mode?
		return entries if @multiple_settings.sort.nil?

		entries.sort_by do |entry|
			count_sort_key(entry)
		end
	end

	# Builds the final reference hashes for the current accumulated entries.
	def references
		materialised_entries.map do |entry|
			build_reference(entry)
		end
	end

	private

	# Returns true when the current mode is count.
	def counted_mode?
		@multiple_settings.count?
	end

	# Appends one entry while recording its first-seen order.
	def append_entry(document:, key:, metadata:, count:)
		entry = {
			document: document,
			key: key,
			metadata: normalise_metadata(metadata),
			count: count,
			first_seen_index: @next_position
		}
		@next_position += 1
		@entries << entry
		entry
	end

	# Builds one stable sort key for counted output.
	def count_sort_key(entry)
		if @multiple_settings.sort_ascending?
			[entry.fetch(:count), entry.fetch(:first_seen_index)]
		else
			[-entry.fetch(:count), entry.fetch(:first_seen_index)]
		end
	end

	# Returns one defensive copy of an entry hash.
	def duplicate_entry(entry)
		{
			document: entry.fetch(:document),
			key: entry.fetch(:key),
			metadata: normalise_metadata(entry.fetch(:metadata)),
			count: entry.fetch(:count),
			first_seen_index: entry.fetch(:first_seen_index)
		}
	end

	# Builds one canonical output reference from an accumulated entry.
	def build_reference(entry)
		@reference_template.build(
			document: entry.fetch(:document),
			key: entry.fetch(:key),
			metadata: entry.fetch(:metadata),
			count: entry.fetch(:count)
		)
	end

	# Merges later metadata under the first-seen metadata.
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
