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
		# Caches the parsed contents of one concrete leaf under a raw path.
		#
		# Each location keeps its own singular/array shape so write-back can
		# upgrade that exact leaf without leaking links across sibling array items.
		class LocationState
			# Builds one concrete-location cache.
			def initialize(match:, string_array:, reference_template:, multiple_settings:)
				@match = match
				@string_array = string_array
				@reference_template = reference_template
				@multiple_settings = multiple_settings
				@shape = infer_shape(@match.value)
				@entries = parse_entries(@match.value)
				@resolution_cache = {}
				@upgraded_value_cache = {}
			end

			# Resolves every parsed entry for one primary-key scheme.
			def resolved_entries_for(primary_path:, &resolver)
				signature = primary_signature(primary_path)
				@resolution_cache[signature] ||= @entries.map do |entry|
					resolver.call(entry)
				end
			end

			# Builds the upgraded value for this exact location.
			def upgraded_value(primary_path:, &resolver)
				signature = primary_signature(primary_path)
				@upgraded_value_cache[signature] ||= begin
					accumulator = build_accumulator

					resolved_entries_for(primary_path: primary_path, &resolver).each do |resolved_entry|
						next unless resolved_entry

						accumulator.add(
							document: resolved_entry.fetch(:document),
							key: resolved_entry.fetch(:key),
							metadata: resolved_entry.fetch(:metadata),
							count: resolved_entry.fetch(:count)
						)
					end
					values = accumulator.references

					(@shape == :array || values.length != 1) ? values : values.first
				end
			end

			# Writes the upgraded value back onto the exact matched location.
			def write_upgraded_value(primary_path:, &resolver)
				@match.write(upgraded_value(primary_path: primary_path, &resolver))
			end

			private

			# Parses one concrete raw value into individual reference entries.
			def parse_entries(raw_value)
				@string_array.interpret(raw_value, split: -1, flatten: true).map do |entry|
					@reference_template.parse(entry)
				end.compact
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

			# Tracks the original top-level shape of this concrete raw value.
			def infer_shape(raw_value)
				raw_value.is_a?(Array) ? :array : :single
			end
		end

		attr_reader :document, :path, :raw_value

		# Builds one raw-path cache for one document and path.
		def initialize(document:, path:, data_path:, string_array:, reference_template:, multiple_settings:)
			@document = document
			@path = path
			@data_path = data_path
			@string_array = string_array
			@reference_template = reference_template
			@multiple_settings = multiple_settings
			@read_result = @data_path.read_result(@document.data, @path)
			@raw_value = @read_result.value
			@present = @read_result.present?
			@location_states = @read_result.matches.map do |match|
				LocationState.new(
					match: match,
					string_array: @string_array,
					reference_template: @reference_template,
					multiple_settings: @multiple_settings
				)
			end
			@preferred_primary_path = nil
		end

		# Returns true when the source path existed in frontmatter.
		def present?
			@present
		end

		# Returns true when resolving the path required expanding across arrays.
		def spans_arrays?
			@read_result.array_traversed?
		end

		# Resolves every parsed entry for one primary-key scheme.
		def resolved_entries_for(primary_path:, registry:)
			@preferred_primary_path ||= primary_path
			@location_states.flat_map do |location_state|
				location_state.resolved_entries_for(primary_path: primary_path) do |entry|
					resolve_entry(entry: entry, primary_path: primary_path, registry: registry)
				end
			end
		end

		# Builds the upgraded path value while preserving its concrete locations.
		def upgraded_raw_value(registry:)
			return nil unless present?

			upgraded_values = upgraded_location_values(registry: registry)
			return upgraded_values.first if upgraded_values.length == 1

			upgraded_values
		end

		# Writes upgraded values back onto the exact matched locations.
		def write_upgraded_input!(registry:)
			upgraded_location_values(registry: registry)
			@location_states.each do |location_state|
				location_state.write_upgraded_value(primary_path: @preferred_primary_path) do |entry|
					resolve_entry(entry: entry, primary_path: @preferred_primary_path, registry: registry)
				end
			end
		end

		private

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

		# Builds upgraded values for every concrete location under this raw path.
		def upgraded_location_values(registry:)
			@location_states.map do |location_state|
				location_state.upgraded_value(primary_path: @preferred_primary_path) do |entry|
					resolve_entry(entry: entry, primary_path: @preferred_primary_path, registry: registry)
				end
			end
		end
	end
end

end

end
end
