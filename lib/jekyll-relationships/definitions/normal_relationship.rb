# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships
module Definitions

# Stores the final configuration for one concrete normal relationship pair.
#
# Each instance describes one source collection, one target collection, and the
# resolved frontmatter rules that apply to links between them.
class NormalRelationship
	attr_reader :from_collection, :to_collection, :primary_path, :foreign_paths,
		:output_path, :sequence, :reads_frontmatter, :bidirectional, :resolver_classes

	# Captures the resolved configuration for one concrete pair.
	def initialize(from_collection:, to_collection:, primary_path:, foreign_paths:, output_path:, debug:, sequence:, reads_frontmatter:, bidirectional:)
		@from_collection = from_collection
		@to_collection = to_collection
		@primary_path = primary_path
		@foreign_paths = foreign_paths
		@output_path = output_path
		@debug = debug
		@sequence = sequence
		@reads_frontmatter = reads_frontmatter
		@bidirectional = bidirectional
		@resolver_classes = []
	end

	# Returns the canonical path on which final links should be written.
	def final_output_path
		@output_path || @foreign_paths.first
	end

	# Returns true when extra debug logging should be emitted for this pair.
	def debug?
		@debug
	end

	# Registers one resolver class against this relationship pair.
	def add_resolver(resolver_class)
		@resolver_classes << resolver_class
	end
end

end
end

end
end
