# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships
module Trees

# Calculates the shortest distance from every tree node to any current root.
#
# The supplied graph-like object must expose `tree_documents`,
# `parent_documents_for`, and `child_documents_for`. Keeping this traversal in
# one helper ensures tree write-back and tree pruning interpret depth the same
# way even though they operate on different graph wrappers.
class RootDistances
	# Returns one map of document object id to shortest root distance.
	def self.for(graph:)
		root_distances = {}
		queue = graph.tree_documents.select do |document|
			graph.parent_documents_for(document).empty?
		end.sort_by(&:relative_path).map do |root_document|
			[root_document, 0]
		end

		until queue.empty?
			document, distance = queue.shift
			existing_distance = root_distances[document.object_id]
			next if !existing_distance.nil? && existing_distance <= distance

			root_distances[document.object_id] = distance
			graph.child_documents_for(document).each do |child_document|
				queue << [child_document, distance + 1]
			end
		end

		root_distances
	end
end

end
end

end
end
