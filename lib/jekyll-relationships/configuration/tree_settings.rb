# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

class Configuration

	# Encapsulates the global tree settings.
	#
	# The object resolves the tree-specific defaults once so the tree graph can
	# ask simple questions such as maximums and frontmatter key names.
	class TreeSettings
		# Builds one tree-settings helper from the raw config.
		def initialize(raw_config:)
			merged_tree = Configuration::HashUtilities.merge_hash(Defaults::TREE, raw_config)
			@frontmatter = Configuration::HashUtilities.merge_hash(
				Defaults::TREE.fetch('frontmatter'),
				Configuration::HashUtilities.fetch_hash_value(merged_tree, 'frontmatter')
			)
			@maximums = Configuration::HashUtilities.merge_hash(
				Defaults::TREE.fetch('max'),
				Configuration::HashUtilities.fetch_hash_value(merged_tree, 'max')
			)
			@url = !!merged_tree['url']
		end

		# Returns the configured tree frontmatter key names.
		def frontmatter
			@frontmatter.dup
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
