# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships
module Definitions

# Stores the final configuration for one tree relationship definition.
#
# Tree relationships define which parent-child collection directions are valid
# and which frontmatter, maximum, URL, and primary-key rules should be used to
# resolve references for this concrete relationship definition.
class TreeRelationship
	attr_reader :from_collection, :to_collection, :primary_path, :tree_settings, :sequence

	# Captures the allowed parent-child directions for one tree definition.
	def initialize(from_collection:, to_collection:, primary_path:, parent_child_pairs:, tree_settings:, debug:, sequence:)
		@from_collection = from_collection
		@to_collection = to_collection
		@primary_path = primary_path
		@parent_child_pairs = parent_child_pairs
		@tree_settings = tree_settings
		@debug = debug
		@sequence = sequence
	end

	# Returns every allowed parent-child direction for this definition.
	def parent_child_pairs
		@parent_child_pairs.dup
	end

	# Returns true when extra debug logging should be emitted for this definition.
	def debug?(area = nil)
		@debug.enabled?(area)
	end

	# Returns true when one event's related IDs satisfy this definition's debug filter.
	def debug_ids_match?(ids)
		@debug.matches_ids?(ids)
	end

	# Returns true when one parent-child direction is permitted.
	def allows_parent_child?(parent_collection:, child_collection:)
		@parent_child_pairs.include?([parent_collection, child_collection])
	end
end

end
end

end
end
