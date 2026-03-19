# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

class Configuration

	# Resolves the tree-specific frontmatter locations for one effective config.
	#
	# Tree frontmatter inherits the active relationship frontmatter base at each
	# override level, but may replace that base with its own `tree.frontmatter.base`.
	# The resolved helper exposes explicit input and output paths so the tree
	# graph never has to reimplement config merging rules.
	class TreeFrontmatter
		PATH_NAMES = %w[parent child parents children ancestors descendants].freeze

		# Builds one tree-frontmatter helper from the resolved values.
		def initialize(base:, raw_paths:, raw_output_path:, string_array:)
			@base = normalise_base(base)
			@raw_paths = stringify_hash(raw_paths)
			@raw_output_path = raw_output_path
			@string_array = string_array
			validate_paths!
		end

		# Builds the built-in default tree frontmatter configuration.
		def self.defaults(string_array:)
			new(
				base: Defaults::FRONTMATTER.fetch('base'),
				raw_paths: Defaults::TREE.fetch('frontmatter'),
				raw_output_path: nil,
				string_array: string_array
			)
		end

		# Returns one cloned helper with one override level merged in.
		#
		# Relationship `frontmatter.base` is applied first for the level, then
		# `tree.frontmatter.base` may replace it for tree paths only.
		def merge_level(frontmatter_override:, tree_frontmatter_override:)
			override_hash = tree_frontmatter_override.is_a?(Hash) ? tree_frontmatter_override : {}
			next_base = base_after_overrides(frontmatter_override: frontmatter_override, tree_frontmatter_override: override_hash)
			next_paths = @raw_paths.dup
			next_output_path = @raw_output_path

			PATH_NAMES.each do |name|
				next unless Configuration::HashUtilities.hash_key?(override_hash, name)

				next_paths[name] = Configuration::HashUtilities.fetch_hash_value(override_hash, name)
			end

			if Configuration::HashUtilities.hash_key?(override_hash, 'output')
				next_output_path = Configuration::HashUtilities.fetch_hash_value(override_hash, 'output')
			end

			self.class.new(
				base: next_base,
				raw_paths: next_paths,
				raw_output_path: next_output_path,
				string_array: @string_array
			)
		end

		# Returns the effective base path applied to tree frontmatter.
		def base
			@base
		end

		# Returns every absolute input path used to read parent references.
		#
		# Single-parent trees only read the singular parent keys, matching the
		# documented contract that plural keys are ignored once the maximum is 1.
		def parent_input_paths(max_parents:)
			return paths_for('parent') if max_parents == 1

			(paths_for('parent') + paths_for('parents')).uniq
		end

		# Returns every absolute input path used to read child references.
		#
		# Single-child trees mirror the parent-side behaviour and only read the
		# singular child keys when the configured maximum is 1.
		def child_input_paths(max_children:)
			return paths_for('child') if max_children == 1

			(paths_for('child') + paths_for('children')).uniq
		end

		# Returns the absolute prevailing singular parent output path.
		def parent_output_path
			first_path_for('parent')
		end

		# Returns the absolute prevailing singular child output path.
		def child_output_path
			first_path_for('child')
		end

		# Returns the absolute prevailing plural parent output path.
		def parents_output_path
			first_path_for('parents')
		end

		# Returns the absolute prevailing plural child output path.
		def children_output_path
			first_path_for('children')
		end

		# Returns the absolute prevailing ancestors output path.
		def ancestors_output_path
			first_path_for('ancestors')
		end

		# Returns the absolute prevailing descendants output path.
		def descendants_output_path
			first_path_for('descendants')
		end

		# Returns the absolute output container path, if one is configured.
		def output_path
			return nil if blank_path?(@raw_output_path)
			raise ConfigurationError, 'Tree frontmatter output must be one path, not an array.' if @raw_output_path.is_a?(Array)

			apply_base(@raw_output_path.to_s.strip)
		end

		# Builds the final tree-output hash for one document.
		#
		# The configured relative tree paths become nested keys within the output
		# hash, while the configured output container path becomes the single
		# frontmatter location on which that hash is written.
		def output_payload(parent_value:, parents_value:, child_value:, children_value:, ancestors_value:, descendants_value:, max_parents:, max_children:)
			payload = {}
			data_path = Jekyll::Plugins::Relationships::Support::DataPath.new

			if max_parents == 1
				data_path.write(payload, first_relative_path_for('parent'), parent_value)
			else
				data_path.write(payload, first_relative_path_for('parents'), parents_value)
			end

			if max_children == 1
				data_path.write(payload, first_relative_path_for('child'), child_value)
			else
				data_path.write(payload, first_relative_path_for('children'), children_value)
			end

			data_path.write(payload, first_relative_path_for('ancestors'), ancestors_value)
			data_path.write(payload, first_relative_path_for('descendants'), descendants_value)
			payload
		end

		private

		# Resolves the next effective base for one override level.
		def base_after_overrides(frontmatter_override:, tree_frontmatter_override:)
			next_base = @base

			if Configuration::HashUtilities.hash_key?(frontmatter_override, 'base')
				next_base = normalise_base(Configuration::HashUtilities.fetch_hash_value(frontmatter_override, 'base'))
			end

			if Configuration::HashUtilities.hash_key?(tree_frontmatter_override, 'base')
				next_base = normalise_base(Configuration::HashUtilities.fetch_hash_value(tree_frontmatter_override, 'base'))
			end

			next_base
		end

		# Returns the configured absolute paths for one tree property.
		def paths_for(name)
			configured_paths_for(name).map { |path| apply_base(path) }
		end

		# Returns the first prevailing absolute path for one tree property.
		def first_path_for(name)
			paths_for(name).first
		end

		# Returns the first prevailing relative path for one tree property.
		def first_relative_path_for(name)
			configured_paths_for(name).first
		end

		# Returns the configured relative paths for one property.
		def configured_paths_for(name)
			raw_value = @raw_paths[name]
			paths = @string_array.interpret(raw_value, split: true, flatten: true).map do |path|
				string_path = path.to_s.strip
				raise ConfigurationError, "Tree frontmatter path `#{name}` cannot be blank." if string_path.empty?

				string_path
			end
			raise ConfigurationError, "Tree frontmatter must define at least one path for `#{name}`." if paths.empty?

			paths.uniq
		end

		# Applies the current base to one relative path.
		def apply_base(path)
			return path if @base.empty?
			return @base if path.to_s.empty?

			"#{@base}.#{path}"
		end

		# Ensures the helper only stores string-keyed frontmatter fields.
		def stringify_hash(hash)
			return {} unless hash.is_a?(Hash)

			hash.each_with_object({}) do |(key, value), stringified|
				stringified[key.to_s] = value
			end
		end

		# Normalises nil bases to the empty string for path resolution.
		def normalise_base(raw_base)
			return '' if raw_base.nil?

			raw_base.to_s
		end

		# Returns true when one configured path is blank or missing.
		def blank_path?(path)
			path.nil? || path.to_s.strip.empty?
		end

		# Validates only the known path-bearing properties eagerly.
		def validate_paths!
			PATH_NAMES.each { |name| configured_paths_for(name) }
			return if blank_path?(@raw_output_path)
			return unless @raw_output_path.is_a?(Array)

			raise ConfigurationError, 'Tree frontmatter output must be one path, not an array.'
		end
	end
end

end

end
end
