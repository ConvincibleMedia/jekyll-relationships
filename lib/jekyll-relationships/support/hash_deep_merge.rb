# frozen_string_literal: true

module Jekyll
module Plugins
module Relationships

module Support
	module_function

	# Deep-merges two hashes without mutating either input.
	#
	# Values from `right_hash` win over values from `left_hash`. Nested hashes are
	# merged recursively, while all other values are treated as leaf replacements.
	def hash_deep_merge(left_hash, right_hash)
		left = stringify_hash(left_hash)
		right = stringify_hash(right_hash)

		left.each_with_object({}) do |(key, value), merged|
			right_value = fetch_hash_value(right, key)

			merged[key] = if value.is_a?(Hash) && right_value.is_a?(Hash)
									hash_deep_merge(value, right_value)
								elsif hash_key?(right, key)
									right_value
								else
									value
								end
		end.tap do |merged|
			right.each do |key, value|
				next if merged.key?(key)

				merged[key] = value
			end
		end
	end

	# Returns true when a string- or symbol-keyed hash contains the given key.
	def hash_key?(hash, key)
		return false unless hash.is_a?(Hash)

		hash.key?(key) || hash.key?(key.to_s) || hash.key?(key.to_sym)
	end

	# Reads one value from a string- or symbol-keyed hash.
	def fetch_hash_value(hash, key)
		return nil unless hash.is_a?(Hash)

		Jekyll::Plugins::Relationships::Support::FrontmatterPath.read_hash(hash, key)
	end

	# Returns one shallow string-keyed copy of a hash.
	def stringify_hash(hash)
		return {} unless hash.is_a?(Hash)

		hash.each_with_object({}) do |(key, value), stringified|
			stringified[key.to_s] = value
		end
	end

end
end
end
end
