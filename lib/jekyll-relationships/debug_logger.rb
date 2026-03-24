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

	# Emits one debug line for one normal relationship state.
	def relationship_event(document:, definition:, area:, event:, details: {})
		return unless definition.debug?(area)

		log(
			area: area,
			prefix: "#{document.relative_path} (#{definition.from_collection} -> #{definition.to_collection}) #{event}",
			details: details
		)
	end

	# Emits one debug line for a document-level write-back event.
	def document_event(document:, definitions:, area:, event:, details: {})
		debug_definitions = Array(definitions).select { |definition| definition.debug?(area) }
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
		return unless definition.debug?(area)

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

	# Emits one line through the standard Jekyll logger.
	def log(area:, prefix:, details:)
		detail_text = details.each_with_object([]) do |(key, value), parts|
			parts << "#{key}=#{format_value(value)}"
		end.join(' ')

		message = detail_text.empty? ? prefix : "#{prefix} #{detail_text}"
		Jekyll.logger.info('Relationships:', "[debug:#{area}] #{message}")
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
