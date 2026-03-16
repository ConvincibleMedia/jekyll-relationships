# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

class Configuration

	# Holds the built-in configuration defaults used when the site omits them.
	module Defaults
		FRONTMATTER = {
			'base' => 'relationships',
			'primary' => nil,
			'foreign' => '<collection>',
			'output' => nil
		}.freeze

		TREE = {
			'frontmatter' => {
				'parent' => 'parent',
				'child' => 'child',
				'parents' => 'parents',
				'children' => 'children',
				'ancestors' => 'ancestors',
				'descendants' => 'descendants'
			}.freeze,
			'max' => {
				'parents' => -1,
				'children' => -1
			}.freeze,
			'url' => false
		}.freeze

		KEYWORDS = {
			'self' => 'self',
			'others' => 'others',
			'all' => 'all',
			'collection' => 'collection',
			'key' => 'key',
			'page' => 'page'
		}.freeze
	end
end

end

end
end
