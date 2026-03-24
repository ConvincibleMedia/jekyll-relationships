# frozen_string_literal: true

module Jekyll
module Plugins
module Relationships

module Support

# Interprets loose config/frontmatter values as arrays.
#
# Use one instance per delimiter configuration, then call `with` to derive
# a nearby variant without restating the full configuration.
class StringArray

	DEFAULT_DELIMITER = ','
	UNSET = Object.new.freeze

	attr_reader :delimiter

	# Builds a string-array helper for one default delimiter.
	def initialize(delimiter: DEFAULT_DELIMITER)
		@delimiter = self.class.normalise_delimiter(delimiter, DEFAULT_DELIMITER)
	end

	# Builds a clone with selected configuration overrides.
	def with(delimiter: UNSET)
		self.class.new(
			delimiter: delimiter.equal?(UNSET) ? @delimiter : delimiter
		)
	end

	# Normalises one configured delimiter.
	#
	# Blank or unsupported values fall back to `default_delimiter`.
	# `false` disables string splitting.
	def self.normalise_delimiter(raw_delimiter, default_delimiter = DEFAULT_DELIMITER)
		return false if raw_delimiter == false
		return default_delimiter unless raw_delimiter.is_a?(String)

		delimiter = raw_delimiter
		return false if delimiter.strip.downcase == 'false'

		delimiter.empty? ? default_delimiter : delimiter
	end

	# Interprets a scalar or array as an array with configurable string
	# splitting depth.
	#
	# `split` modes:
	# - `true` / `0`: split only a top-level string
	# - `false`: never split strings, only wrap
	# - positive integer: split strings found at that array depth
	# - `-1`: split strings at any depth
	#
	# `flatten: true` promotes split values into the surrounding array.
	# `flatten: false` keeps split values nested at the point they arose.
	def interpret(value, split: true, flatten: false, delimiter: UNSET)
		active_delimiter = effective_delimiter(delimiter)
		active_split_depth = normalise_split_depth(split)
		interpret_value(value, split_depth: active_split_depth, flatten: !!flatten, current_level: 0, delimiter: active_delimiter)
	end

	private

	# Interprets one value at one traversal depth.
	def interpret_value(value, split_depth:, flatten:, current_level:, delimiter:)
		return [] if value.nil?
		return interpret_array(value, split_depth: split_depth, flatten: flatten, current_level: current_level, delimiter: delimiter) if value.is_a?(Array)
		return interpret_string(value, split_depth: split_depth, current_level: current_level, delimiter: delimiter) if value.is_a?(String)

		[value]
	end

	# Interprets one array and recursively flattens nested array structure
	# while respecting string-splitting depth.
	def interpret_array(array, split_depth:, flatten:, current_level:, delimiter:)
		array.flatten(1).compact.each_with_object([]) do |entry, interpreted|
			if entry.is_a?(Array)
				interpreted.concat(
					interpret_array(
						entry,
						split_depth: split_depth,
						flatten: flatten,
						current_level: current_level + 1,
						delimiter: delimiter
					)
				)
				next
			end

			if entry.is_a?(String)
				string_value = interpret_string(entry, split_depth: split_depth, current_level: current_level + 1, delimiter: delimiter)
				if should_split_string?(split_depth, current_level + 1) && !flatten && string_value.length > 1
					interpreted << string_value
				else
					interpreted.concat(string_value)
				end
				next
			end

			interpreted << entry
		end
	end

	# Interprets one string according to the configured split depth.
	def interpret_string(value, split_depth:, current_level:, delimiter:)
		return [value] unless should_split_string?(split_depth, current_level)

		split_string(value, delimiter)
	end

	# Splits one string with the active delimiter, trimming and discarding
	# blank entries.
	def split_string(value, delimiter)
		if delimiter == false
			entry = value.to_s.strip
			return [] if entry.empty?

			return [entry]
		end

		split_pattern = Regexp.new(Regexp.escape(delimiter.to_s))
		value.to_s.split(split_pattern, -1).map(&:strip).reject(&:empty?)
	end

	# Resolves whether strings should be split at the current array depth.
	def should_split_string?(split_depth, current_level)
		return false if split_depth == false
		return true if split_depth == -1

		current_level == split_depth
	end

	# Normalises the configured split depth.
	def normalise_split_depth(raw_split)
		return false if raw_split == false
		return 0 if raw_split == true
		return raw_split if raw_split.is_a?(Integer)

		return raw_split.to_i if raw_split.is_a?(String) && raw_split.strip.match?(/\A-?\d+\z/)

		raise ArgumentError, "Unsupported string-array split depth '#{raw_split}'."
	end

	# Resolves one optional delimiter override against the instance
	# default.
	def effective_delimiter(raw_override)
		return @delimiter if raw_override.equal?(UNSET)

		self.class.normalise_delimiter(raw_override, @delimiter)
	end
end

end
end
end
end
