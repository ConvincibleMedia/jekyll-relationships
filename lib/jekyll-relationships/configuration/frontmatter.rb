# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

class Configuration

	# Encapsulates one merged frontmatter configuration block.
	#
	# Instances resolve `base`, `primary`, `scope`, `foreign`, and `output` paths so the
	# rest of the engine can work with explicit values only.
	class Frontmatter
		# Describes one configured scope field while preserving both its public name and its base-resolved document path.
		ScopeField = Struct.new(:name, :path) do
			# Returns a stable value signature suitable for registry cache keys.
			def signature
				[name, path]
			end
		end

		# Builds one frontmatter configuration helper.
		def initialize(raw_config:, string_array:)
			@raw_config = raw_config.is_a?(Hash) ? raw_config : {}
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

		# Returns the configured scope fields with their literal reference keys and resolved document paths.
		def scope_fields
			raw_scope = fetch_value('scope')
			return [] if raw_scope.nil?
			unless raw_scope.is_a?(String) || raw_scope.is_a?(Array)
				raise ConfigurationError, '`frontmatter.scope` must be a string, comma-delimited string, or array of non-empty path strings.'
			end

			raw_paths = raw_scope.is_a?(String) ? @string_array.interpret(raw_scope, split: true, flatten: true) : raw_scope
			if raw_paths.empty? || raw_paths.any? { |path| !path.is_a?(String) || path.strip.empty? }
				raise ConfigurationError, '`frontmatter.scope` must contain one or more non-empty path strings.'
			end

			raw_paths.map do |path|
				name = path.strip
				ScopeField.new(name, apply_base(name)).freeze
			end.uniq { |field| field.name }
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
			Jekyll::Plugins::Relationships::Support::Placeholders::COLLECTION
		end
	end
end

end

end
end
