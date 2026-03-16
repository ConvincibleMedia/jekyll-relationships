# frozen_string_literal: true

require 'jekyll'
require 'set'

require 'jekyll-relationships/version'
require 'jekyll-relationships/errors'
require 'jekyll-relationships/support/string_array'
require 'jekyll-relationships/support/frontmatter_path'
require 'jekyll-relationships/support/data_path'
require 'jekyll-relationships/reference_template'
require 'jekyll-relationships/configuration'
require 'jekyll-relationships/document_registry'
require 'jekyll-relationships/tree_graph'
require 'jekyll-relationships/resolvers/base'
require 'jekyll-relationships/engine'
require 'jekyll-relationships/generator'

module Jekyll
module Plugins
	module Relationships
	end
end
end
