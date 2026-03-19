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
require 'jekyll-relationships/debug_logger'
require 'jekyll-relationships/run_logger'
require 'jekyll-relationships/definitions/configured_relationship'
require 'jekyll-relationships/definitions/prune_rule'
require 'jekyll-relationships/pruning/rule_pruner'
require 'jekyll-relationships/pruning/normal_graph'
require 'jekyll-relationships/pruning/tree_provenance'
require 'jekyll-relationships/pruning/tree_phase'
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
