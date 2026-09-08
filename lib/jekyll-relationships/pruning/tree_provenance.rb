# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships
module Pruning

# Captures the original accepted parent ordering for every tree document.
#
# Tree orphan repair needs stable provenance even after many prune rounds. This
# helper snapshots the first fully built tree graph before any pruning so later
# orphan handling can reattach nearest surviving ancestors in deterministic order.
class TreeProvenance
	# Builds one immutable provenance index from one tree graph.
	def initialize(tree_graph:)
		@original_parent_entries_by_child_id = tree_graph.tree_documents.each_with_object({}) do |document, entries|
			entries[document.object_id] = tree_graph.parent_edge_entries_for(document)
		end
	end

	# Returns the original ordered parent-edge entries for one document.
	def original_parent_entries_for(document)
		Array(@original_parent_entries_by_child_id[document.object_id]).map(&:dup)
	end
end

end
end

end
end
