# frozen_string_literal: true

module Jekyll
module Plugins
module Relationships

module Support

# Matches exact values at dot-separated paths in document frontmatter.
#
# Paths traverse hashes only so arrays and hashes remain matchable terminal
# values. Lookup distinguishes a missing path from a present nil value and
# treats string and symbol hash keys as equivalent.
class FrontmatterMatcher
	# Builds one matcher from normalised path and expected-value pairs.
	def initialize(expected_values:)
		@expected_values = expected_values
	end

	# Returns true when every configured path is present and matches exactly.
	def matches?(data)
		@expected_values.all? do |path, expected_value|
			match = value_at(data: data, path: path)
			match.fetch(:present) && type_sensitive_equal?(match.fetch(:value), expected_value)
		end
	end

	private

	# Reads one hash-only path without collapsing a present nil into missing.
	def value_at(data:, path:)
		current_value = data
		FrontmatterPath.split_path(path).each do |segment|
			return missing_value unless current_value.is_a?(Hash)

			resolved_key = resolve_hash_key(hash: current_value, segment: segment)
			return missing_value if resolved_key.nil?

			current_value = current_value[resolved_key]
		end

		{
			present: true,
			value: current_value
		}
	end

	# Resolves string and symbol forms of one path segment.
	def resolve_hash_key(hash:, segment:)
		return segment if hash.key?(segment)

		symbol_segment = segment.to_sym
		return symbol_segment if hash.key?(symbol_segment)

		nil
	end

	# Returns one fresh missing lookup result.
	def missing_value
		{
			present: false,
			value: nil
		}
	end

	# Requires both the Ruby type and value to match.
	def type_sensitive_equal?(actual_value, expected_value)
		actual_value.class == expected_value.class && actual_value == expected_value
	end
end

end

end
end
end
