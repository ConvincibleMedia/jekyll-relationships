# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships
module Pruning

# Applies configured prune-rule predicates to a mutable graph view.
#
# The graph view may represent either resolved normal relationships or the
# current tree adjacency. Pruning is recursive within the supplied graph because
# removing one document can make relationship predicates select others.
class RulePruner
	# Builds one pruner over one mutable graph view and one ordered rule list.
	def initialize(graph:, rules:, subject_documents_resolver: nil)
		@graph = graph
		@rules = Array(rules)
		@subject_documents_resolver = subject_documents_resolver
	end

	# Removes documents until no configured rule selects another candidate.
	def prune!
		removed_documents = []

		loop do
			candidates = prune_candidates
			break if candidates.empty?

			candidates.each_value do |document|
				next unless @graph.remove_document(document)

				removed_documents << document
			end
		end

		removed_documents
	end

	private

	# Finds every document selected by at least one prune rule.
	def prune_candidates
		@rules.each_with_object({}) do |rule, candidates|
			subject_documents_for(rule).each do |document|
				next if candidates.key?(document.object_id)
				next unless rule.frontmatter_selected?(document)
				next unless rule.relationship_selected?(graph: @graph, document: document)

				candidates[document.object_id] = document
			end
		end
	end

	# Returns the subject documents one rule is currently allowed to prune.
	def subject_documents_for(rule)
		return @subject_documents_resolver.call(rule, @graph) if @subject_documents_resolver

		@graph.documents_for(rule.subject_collection)
	end
end

end
end

end
end
