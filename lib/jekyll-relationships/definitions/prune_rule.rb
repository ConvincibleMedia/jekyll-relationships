# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships
module Definitions

# Stores one fully expanded prune rule for one subject collection.
#
# Raw relationship entries may expand into many concrete relationship members.
# After the global prune settings have been applied, each expanded prune rule
# targets exactly one subject collection and one set of configured relationship
# members whose neighbour counts should be combined for that subject.
class PruneRule
	attr_reader :kind, :subject_collection, :members, :min, :depth, :entry_index

	# Captures one immutable prune rule.
	def initialize(kind:, subject_collection:, members:, min:, depth:, inverse:, entry_index:)
		@kind = kind
		@subject_collection = subject_collection
		@members = members.sort_by(&:sequence).freeze
		@min = min
		@depth = depth
		@inverse = inverse
		@entry_index = entry_index
	end

	# Returns true when the rule targets the inverse side of the relationship.
	def inverse?
		@inverse
	end

	# Returns true when this rule prunes a tree relationship subject.
	def tree?
		@kind == :tree
	end

	# Returns true when this rule prunes a normal relationship subject.
	def normal?
		@kind == :normal
	end

	# Returns the combined neighbour documents for one subject document.
	def neighbour_documents(graph:, document:)
		@members.each_with_object({}) do |member, neighbours|
			member.neighbour_documents(
				graph: graph,
				document: document,
				inverse: inverse?
			).each do |neighbour|
				neighbours[neighbour.object_id] ||= neighbour
			end
		end.values
	end

	# Returns every member identifier used by the rule for overlap checks.
	def member_identifiers
		@members.map(&:identifier)
	end
end

end
end

end
end
