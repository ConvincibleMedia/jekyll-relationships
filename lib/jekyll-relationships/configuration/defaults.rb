# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

class Configuration

	# Holds the built-in configuration defaults used when the site omits them.
	module Defaults
		ENABLED = true
		DEBUG = false

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

		MULTIPLE = {
			'mode' => 'count',
			'sort' => nil
		}.freeze

		KEYWORDS = {
			'self' => 'self',
			'others' => 'others',
			'all' => 'all'
		}.freeze
	end
end

end

end
end
