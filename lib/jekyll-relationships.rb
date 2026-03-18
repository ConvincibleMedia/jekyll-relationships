# frozen_string_literal: true

require 'jekyll'
require 'set'

require 'jekyll-relationships/version'
require 'jekyll-relationships/errors'
require 'jekyll-relationships/support/string_array'
require 'jekyll-relationships/support/frontmatter_path'
require 'jekyll-relationships/support/data_path'
require 'jekyll-relationships/support/hash_deep_merge'
require 'jekyll-relationships/support/placeholders'
require 'jekyll-relationships/references/template'
require 'jekyll-relationships/references/accumulator'
require 'jekyll-relationships/configuration'
require 'jekyll-relationships/documents/registry'
require 'jekyll-relationships/resolvers/base'
require 'jekyll-relationships/engine'
require 'jekyll-relationships/generators/relationships'

module Jekyll
module Plugins
	module Relationships
	end
end
end
