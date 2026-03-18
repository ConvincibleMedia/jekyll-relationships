# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

class Engine

	# Caches the parsed contents of one raw foreign-path input.
	#
	# The state parses a document path once, then reuses its parsed entries and
	# resolved documents across any number of relationship pairs.
	class RawPathState
		attr_reader :document, :path

		# Builds one raw-path cache for one document and path.
		def initialize(document:, path:, data_path:, string_array:, reference_template:, multiple_settings:)
			@document = document
			@path = path
			@data_path = data_path
			@string_array = string_array
			@reference_template = reference_template
			@multiple_settings = multiple_settings
			@raw_value = @data_path.read(@document.data, @path)
			@present = !@raw_value.nil?
			@shape = infer_shape(@raw_value)
			@entries = parse_entries(@raw_value)
			@resolution_cache = {}
			@preferred_primary_path = nil
		end

		# Returns true when the source path existed in frontmatter.
		def present?
			@present
		end

		# Resolves every parsed entry for one primary-key scheme.
		def resolved_entries_for(primary_path:, registry:)
			signature = primary_signature(primary_path)
			@preferred_primary_path ||= primary_path
			@resolution_cache[signature] ||= @entries.map do |entry|
				resolve_entry(entry: entry, primary_path: primary_path, registry: registry)
			end
		end

		# Builds the upgraded original-path value for write-back.
		def upgraded_value(registry:)
			return nil unless present?

			signature = primary_signature(@preferred_primary_path)
			resolved_entries = @resolution_cache[signature] || []
			accumulator = build_accumulator

			resolved_entries.each do |resolved_entry|
				next unless resolved_entry

				accumulator.add(
					document: resolved_entry.fetch(:document),
					key: resolved_entry.fetch(:key),
					metadata: resolved_entry.fetch(:metadata),
					count: resolved_entry.fetch(:count)
				)
			end
			values = accumulator.references

			return values if @shape == :array || values.length != 1

			values.first
		end

		private

		# Parses one raw value into individual reference entries.
		def parse_entries(raw_value)
			@string_array.interpret(raw_value, split: -1, flatten: true).map do |entry|
				@reference_template.parse(entry)
			end.compact
		end

		# Resolves one parsed entry to a document and canonical key.
		def resolve_entry(entry:, primary_path:, registry:)
			document = if entry.document?
									 entry.page
								 else
									 registry.lookup(
										 key: entry.key,
										 primary_path: primary_path,
										 collection: entry.collection.nil? ? nil : entry.collection.to_s
									 )
								 end

			{
				document: document,
				key: registry.key_for(document, primary_path: primary_path),
				metadata: entry.metadata,
				count: entry.count
			}
		end

		# Builds one new accumulator with the active duplicate-handling settings.
		def build_accumulator
			Jekyll::Plugins::Relationships::References::Accumulator.new(
				reference_template: @reference_template,
				multiple_settings: @multiple_settings
			)
		end

		# Normalises the cache key for one primary-key scheme.
		def primary_signature(primary_path)
			primary_path.nil? ? '__relative_path__' : primary_path
		end

		# Tracks the original top-level shape of a raw path value.
		def infer_shape(raw_value)
			raw_value.is_a?(Array) ? :array : :single
		end
	end
end

end

end
end
