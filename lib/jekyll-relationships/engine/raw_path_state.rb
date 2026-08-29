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
			def initialize(match:, string_array:, reference_template:, reference_context: nil)
				@string_array = string_array
				@reference_template = reference_template
				@reference_context = reference_context
				@entries = parse_entries(match.value)
				@resolution_cache = {}
			end

			# Resolves every parsed entry for one complete identity scheme.
			def resolved_entries_for(primary_path:, scope_fields:, &resolver)
				signature = identity_signature(primary_path: primary_path, scope_fields: scope_fields)
				@resolution_cache[signature] ||= @entries.map do |entry|
					resolver.call(entry)
				end
			end

			private

			# Parses one concrete raw value into individual reference entries.
			def parse_entries(raw_value)
				@string_array.interpret(raw_value, split: -1, flatten: true).map do |entry|
					@reference_template.parse(entry, context: @reference_context)
				end.compact
			end

			# Normalises the cache key for one primary-key and scope scheme.
			def identity_signature(primary_path:, scope_fields:)
				[primary_path.nil? ? '__relative_path__' : primary_path, scope_fields.map(&:signature)]
			end
		end

		attr_reader :document, :path, :raw_value

		# Builds one raw-path cache for one document and path.
		def initialize(document:, path:, data_path:, string_array:, reference_template:, reference_context: nil)
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
					reference_template: @reference_template,
					reference_context: reference_context
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

		# Resolves every parsed entry for one complete identity scheme.
		def resolved_entries_for(primary_path:, scope_fields: [], registry:, relationship: nil, active_document_checker: nil)
			@location_states.flat_map do |location_state|
				location_state.resolved_entries_for(primary_path: primary_path, scope_fields: scope_fields) do |entry|
					resolve_entry(
						entry: entry,
						primary_path: primary_path,
						scope_fields: scope_fields,
						registry: registry,
						relationship: relationship,
						active_document_checker: active_document_checker
					)
				end
			end
		end

		private

		# Resolves one parsed entry to a document and canonical key.
		def resolve_entry(entry:, primary_path:, scope_fields:, registry:, relationship:, active_document_checker:)
			effective_scope = registry.effective_scope_for(
				reference_scope: entry.scope,
				referring_document: @document,
				scope_fields: scope_fields,
				relationship: relationship
			)
			document = if entry.document?
				registry.validate_scope_match!(
					document: entry.page,
					scope: effective_scope,
					scope_fields: scope_fields,
					relationship: relationship,
					referring_document: @document
				)
				entry.page
			else
				registry.lookup(
					key: entry.key,
					primary_path: primary_path,
					collection: entry.collection.nil? ? nil : entry.collection.to_s,
					scope_fields: scope_fields,
					scope: effective_scope,
					relationship: relationship,
					referring_document: @document
				)
			end
			return nil if active_document_checker && !active_document_checker.call(document)

			{
				document: document,
				key: registry.key_for(document, primary_path: primary_path),
				scope: effective_scope,
				metadata: entry.metadata,
				count: entry.count
			}
		end

	end
end

end

end
end
