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
			Jekyll::Plugins::Relationships::Support.hash_deep_merge(base_hash, override_hash)
		end

		# Converts one config value to an integer with a helpful error.
		def integer_value(value, context)
			return value if value.is_a?(Integer)
			return value.to_i if value.is_a?(String) && value.strip.match?(/\A-?\d+\z/)

			raise ConfigurationError, "`#{context}` must be an integer."
		end

		# Converts one config value to a boolean with a helpful error.
		def boolean_value(value, context)
			return value if value == true || value == false
			return true if value.is_a?(String) && value.strip.casecmp('true').zero?
			return false if value.is_a?(String) && value.strip.casecmp('false').zero?

			raise ConfigurationError, "`#{context}` must be true or false."
		end
	end
end

end

end
end
