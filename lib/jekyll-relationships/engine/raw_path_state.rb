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
		# Each location keeps its own parsed entries so repeated resolution can
		# reuse them without reparsing frontmatter.
		class LocationState
			# Builds one concrete-location cache.
			def initialize(match:, string_array:, reference_template:)
				@string_array = string_array
				@reference_template = reference_template
				@entries = parse_entries(match.value)
				@resolution_cache = {}
			end

			# Resolves every parsed entry for one primary-key scheme.
			def resolved_entries_for(primary_path:, &resolver)
				signature = primary_signature(primary_path)
				@resolution_cache[signature] ||= @entries.map do |entry|
					resolver.call(entry)
				end
			end

			private

			# Parses one concrete raw value into individual reference entries.
			def parse_entries(raw_value)
				@string_array.interpret(raw_value, split: -1, flatten: true).map do |entry|
					@reference_template.parse(entry)
				end.compact
			end

			# Normalises the cache key for one primary-key scheme.
			def primary_signature(primary_path)
				primary_path.nil? ? '__relative_path__' : primary_path
			end
		end

		attr_reader :document, :path, :raw_value

		# Builds one raw-path cache for one document and path.
		def initialize(document:, path:, data_path:, string_array:, reference_template:)
			@document = document
			@path = path
			@data_path = data_path
			@string_array = string_array
			@reference_template = reference_template
			@read_result = @data_path.read_result(@document.data, @path)
			@raw_value = @read_result.value
			@present = @read_result.present?
			@location_states = @read_result.matches.map do |match|
				LocationState.new(
					match: match,
					string_array: @string_array,
					reference_template: @reference_template
				)
			end
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
		def resolved_entries_for(primary_path:, registry:, active_document_checker: nil)
			@location_states.flat_map do |location_state|
				location_state.resolved_entries_for(primary_path: primary_path) do |entry|
					resolve_entry(
						entry: entry,
						primary_path: primary_path,
						registry: registry,
						active_document_checker: active_document_checker
					)
				end
			end
		end

		private

		# Resolves one parsed entry to a document and canonical key.
		def resolve_entry(entry:, primary_path:, registry:, active_document_checker:)
			document = if entry.document?
									 entry.page
								 else
									 registry.lookup(
										 key: entry.key,
										 primary_path: primary_path,
										 collection: entry.collection.nil? ? nil : entry.collection.to_s
										 )
									 end
			return nil if active_document_checker && !active_document_checker.call(document)

			{
				document: document,
				key: registry.key_for(document, primary_path: primary_path),
				metadata: entry.metadata,
				count: entry.count
			}
		end

	end
end

end

end
end
