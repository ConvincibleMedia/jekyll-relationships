# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships
module Definitions

# Stores one forward-facing relationship member exactly as it was configured.
#
# These members preserve the original relationship-entry direction even when the
# engine creates additional reverse normal relationships internally for
# bidirectional behaviour. The same member metadata is reused by pruning and the
# default summary logging so the directional semantics stay centralised.
class ConfiguredRelationship
	attr_reader :definition, :kind, :mode, :sequence

	# Captures one configured relationship member.
	def initialize(definition:, kind:, mode:, sequence:)
		@definition = definition
		@kind = kind
		@mode = mode
		@sequence = sequence
	end

	# Returns the configured source collection.
	def from_collection
		@definition.from_collection
	end

	# Returns the configured target collection.
	def to_collection
		@definition.to_collection
	end

	# Returns true when this member represents a normal relationship.
	def normal?
		@kind == :normal
	end

	# Returns true when this member represents a tree relationship.
	def tree?
		@kind == :tree
	end

	# Returns one stable identifier for overlap checks and graph lookups.
	def identifier
		[@kind, from_collection, to_collection, @mode]
	end

	# Returns the direct neighbour documents for one subject document.
	def neighbour_documents(graph:, document:, inverse: false)
		graph.neighbour_documents_for_member(member: self, document: document, inverse: inverse)
	end
end

end
end

end
end
