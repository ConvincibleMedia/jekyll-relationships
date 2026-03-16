# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

class Configuration

	# Encapsulates one effective tree configuration scope.
	#
	# Tree settings are merged level by level so relationship-level
	# `frontmatter.base` overrides can replace higher-level tree bases before a
	# lower-level `tree.frontmatter.base` optionally replaces them again.
	class TreeSettings
		attr_reader :frontmatter

		# Builds one tree-settings helper from already-resolved values.
		def initialize(frontmatter:, maximums:, url:)
			@frontmatter = frontmatter
			@maximums = Configuration::HashUtilities.merge_hash(Defaults::TREE.fetch('max'), maximums)
			@url = !!url
		end

		# Builds the built-in default tree settings.
		def self.defaults(string_array:)
			new(
				frontmatter: TreeFrontmatter.defaults(string_array: string_array),
				maximums: Defaults::TREE.fetch('max'),
				url: Defaults::TREE.fetch('url')
			)
		end

		# Returns one cloned helper with one override level merged in.
		def merge_level(frontmatter_override:, tree_override:)
			override_hash = tree_override.is_a?(Hash) ? tree_override : {}
			next_frontmatter = @frontmatter.merge_level(
				frontmatter_override: frontmatter_override,
				tree_frontmatter_override: Configuration::HashUtilities.fetch_hash_value(override_hash, 'frontmatter')
			)
			next_maximums = Configuration::HashUtilities.merge_hash(
				@maximums,
				Configuration::HashUtilities.fetch_hash_value(override_hash, 'max')
			)
			next_url = Configuration::HashUtilities.hash_key?(override_hash, 'url') ? !!Configuration::HashUtilities.fetch_hash_value(override_hash, 'url') : @url

			self.class.new(
				frontmatter: next_frontmatter,
				maximums: next_maximums,
				url: next_url
			)
		end

		# Returns the configured maximum parent count.
		def max_parents
			Configuration::HashUtilities.integer_value(@maximums['parents'], 'tree.max.parents')
		end

		# Returns the configured maximum child count.
		def max_children
			Configuration::HashUtilities.integer_value(@maximums['children'], 'tree.max.children')
		end

		# Returns true when URL-derived tree inference is enabled.
		def url?
			@url
		end
	end
end

end

end
end
