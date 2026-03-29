# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

# Formats and emits debug output for relationship processing.
#
# This helper keeps all debug messages consistent while still using the built-in
# Jekyll logger. Callers should pass only already-resolved runtime state.
class DebugLogger
	MAX_VALUE_LENGTH = 500
	STRING_ID_PROPERTIES = %w[
		id
		key
		target_key
		reference
		result
		references
		entries
		value
		parent_value
		child_value
		ancestors_value
		descendants_value
	].freeze

	# Builds one logger with the active reference key property for hash parsing.
	def initialize(reference_key_property:)
		@reference_key_property = reference_key_property.to_s
		@data_path = Jekyll::Plugins::Relationships::Support::DataPath.new
	end

	# Emits one debug line for one normal relationship state.
	def relationship_event(document:, definition:, area:, event:, details: {})
		return unless should_log?(definition: definition, area: area, document: document, details: details)

		log(
			area: area,
			prefix: "#{document.relative_path} (#{definition.from_collection} -> #{definition.to_collection}) #{event}",
			details: details
		)
	end

	# Emits one debug line for a document-level write-back event.
	def document_event(document:, definitions:, area:, event:, details: {})
		debug_definitions = Array(definitions).select do |definition|
			should_log?(definition: definition, area: area, document: document, details: details)
		end
		return if debug_definitions.empty?

		log(
			area: area,
			prefix: "#{document.relative_path} #{event}",
			details: details.merge(
				relationships: debug_definitions.map do |definition|
					"#{definition.from_collection}->#{definition.to_collection}"
				end
			)
		)
	end

	# Emits one debug line for one tree relationship event.
	def tree_event(document:, definition:, area:, event:, details: {})
		return unless should_log?(definition: definition, area: area, document: document, details: details)

		log(
			area: area,
			prefix: "#{document.relative_path} (tree #{definition.from_collection} <-> #{definition.to_collection}) #{event}",
			details: details
		)
	end

	# Returns a stable display name for one resolver class.
	def resolver_name(resolver_class)
		resolver_class.name || resolver_class.to_s
	end

	# Formats one arbitrary value for safe debug logging.
	def format_value(value)
		truncate_string(normalise_value(value).inspect)
	end

	private

	# Returns true when one definition wants this area and its ID filter matches.
	def should_log?(definition:, area:, document:, details:)
		return false unless definition.debug?(area)

		definition.debug_ids_match?(related_ids_for(definition: definition, document: document, details: details))
	end

	# Collects every document or reference ID that one event obviously touches.
	def related_ids_for(definition:, document:, details:)
		([document_key(document, primary_path: definition.primary_path)] + extract_related_ids(
			details,
			primary_path: definition.primary_path
		)).compact.uniq
	end

	# Emits one line through the standard Jekyll logger.
	def log(area:, prefix:, details:)
		detail_text = details.each_with_object([]) do |(key, value), parts|
			parts << "#{key}=#{format_value(value)}"
		end.join(' ')

		message = detail_text.empty? ? prefix : "#{prefix} #{detail_text}"
		Jekyll.logger.info('Relationships:', "[debug:#{area}] #{message}")
	end

	# Resolves one document back to the primary key used by the active definition.
	def document_key(document, primary_path:)
		return nil unless document.is_a?(Jekyll::Document)

		if primary_path.nil?
			document.relative_path.sub(/\A_/, '').sub(/#{Regexp.escape(document.extname)}\z/, '')
		else
			value = @data_path.read(document.data, primary_path)
			value.nil? ? nil : value.to_s
		end
	end

	# Walks one debug payload and extracts any obvious relationship IDs from it.
	def extract_related_ids(value, primary_path:, property_name: nil)
		case value
		when Jekyll::Document
			[document_key(value, primary_path: primary_path)].compact
		when Array
			value.flat_map do |item|
				extract_related_ids(item, primary_path: primary_path, property_name: property_name)
			end
		when Hash
			extract_related_ids_from_hash(value, primary_path: primary_path)
		when String
			return [] unless property_name && STRING_ID_PROPERTIES.include?(property_name.to_s)

			trimmed_value = value.strip
			trimmed_value.empty? ? [] : [trimmed_value]
		else
			[]
		end
	end

	# Reads likely ID-bearing properties from one debug hash before recurring.
	def extract_related_ids_from_hash(hash, primary_path:)
		ids = []
		hash.each do |key, value|
			string_key = key.to_s
			if string_key == @reference_key_property || string_key == 'id'
				trimmed_value = value.to_s.strip
				ids << trimmed_value unless trimmed_value.empty?
			end

			ids.concat(
				extract_related_ids(
					value,
					primary_path: primary_path,
					property_name: string_key
				)
			)
		end
		ids.uniq
	end

	# Normalises values so large document objects stay readable in logs.
	def normalise_value(value)
		case value
		when Jekyll::Document
			value.relative_path
		when Array
			value.map { |item| normalise_value(item) }
		when Hash
			value.each_with_object({}) do |(key, nested_value), normalised|
				next if key.to_s == 'page'

				normalised[key] = normalise_value(nested_value)
			end
		else
			value
		end
	end

	# Truncates long debug payloads so one line stays scan-friendly.
	def truncate_string(value)
		return value if value.length <= MAX_VALUE_LENGTH

		"#{value[0, MAX_VALUE_LENGTH - 3]}..."
	end
end

end

end
end
