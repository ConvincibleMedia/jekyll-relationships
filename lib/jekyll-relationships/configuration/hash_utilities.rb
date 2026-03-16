# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

class Configuration

	# Provides shared hash-reading helpers for configuration components.
	module HashUtilities
		module_function

		# Returns true when a string- or symbol-keyed hash includes one key.
		def hash_key?(hash, key)
			return false unless hash.is_a?(Hash)

			hash.key?(key) || hash.key?(key.to_s) || hash.key?(key.to_sym)
		end

		# Reads one string- or symbol-keyed hash value.
		def fetch_hash_value(hash, key)
			return nil unless hash.is_a?(Hash)

			Jekyll::Plugins::Relationships::Support::FrontmatterPath.read_hash(hash, key)
		end

		# Deep-merges two hashes without mutating either.
		def merge_hash(base_hash, override_hash)
			base = base_hash.is_a?(Hash) ? base_hash : {}
			override = override_hash.is_a?(Hash) ? override_hash : {}

			base.each_with_object({}) do |(key, value), merged|
				string_key = key.to_s
				override_value = fetch_hash_value(override, string_key)

				merged[string_key] = if value.is_a?(Hash)
														 merge_hash(value, override_value)
													 elsif override.key?(string_key) || override.key?(string_key.to_sym)
														 override_value
													 else
														 value
													 end
			end.tap do |merged|
				override.each do |key, value|
					string_key = key.to_s
					next if merged.key?(string_key)

					merged[string_key] = value
				end
			end
		end

		# Converts one config value to an integer with a helpful error.
		def integer_value(value, context)
			return value if value.is_a?(Integer)
			return value.to_i if value.is_a?(String) && value.strip.match?(/\A-?\d+\z/)

			raise ConfigurationError, "`#{context}` must be an integer."
		end
	end
end

end

end
end
