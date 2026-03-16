# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

class Configuration

	# Encapsulates one merged frontmatter configuration block.
	#
	# Instances resolve `base`, `primary`, `foreign`, and `output` paths so the
	# rest of the engine can work with explicit values only.
	class Frontmatter
		# Builds one frontmatter configuration helper.
		def initialize(raw_config:, keywords:, string_array:)
			@raw_config = raw_config.is_a?(Hash) ? raw_config : {}
			@keywords = keywords
			@string_array = string_array
		end

		# Returns the configured base path.
		def base
			raw_base = fetch_value('base')
			return '' if raw_base.nil?

			raw_base.to_s
		end

		# Returns the resolved primary-key path, or nil for the default key rule.
		def primary_path
			raw_primary = fetch_value('primary')
			return nil if raw_primary.nil?

			apply_base(raw_primary.to_s)
		end

		# Returns the resolved foreign input paths for one target collection.
		def foreign_paths_for(to_collection:)
			raw_foreign = fetch_value('foreign')
			paths = @string_array.interpret(raw_foreign, split: true, flatten: true)
			raise ConfigurationError, 'Each normal relationship must define at least one foreign path.' if paths.empty?

			paths.map do |path|
				string_path = path.to_s.strip
				raise ConfigurationError, 'Foreign paths cannot be blank.' if string_path.empty?

				resolve_collection_path(path: string_path, to_collection: to_collection)
			end.uniq
		end

		# Returns the resolved output path, if one is configured.
		def output_path_for(to_collection:)
			raw_output = fetch_value('output')
			return nil if raw_output.nil? || raw_output.to_s.strip.empty?

			resolve_collection_path(path: raw_output.to_s.strip, to_collection: to_collection)
		end

		# Returns one arbitrary path with the active base applied.
		def path_with_base(path)
			apply_base(path.to_s)
		end

		# Returns a cloned frontmatter configuration with one override merged in.
		def merge(raw_override)
			self.class.new(
				raw_config: Configuration::HashUtilities.merge_hash(@raw_config, raw_override),
				keywords: @keywords,
				string_array: @string_array
			)
		end

		private

		# Reads one configured property from the raw hash.
		def fetch_value(key)
			Configuration::HashUtilities.fetch_hash_value(@raw_config, key)
		end

		# Applies the active base path to one relative path.
		def apply_base(path)
			return path if base.empty?
			return base if path.to_s.empty?

			"#{base}.#{path}"
		end

		# Resolves one path that may include the active collection placeholder.
		def resolve_collection_path(path:, to_collection:)
			apply_base(path.gsub(collection_placeholder, to_collection))
		end

		# Returns the active `<collection>` placeholder token.
		def collection_placeholder
			"<#{@keywords.fetch('collection')}>"
		end
	end
end

end

end
end
