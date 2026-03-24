# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships
module Pruning

# Stores the resolved normal-relationship graph for one active session.
#
# The graph keeps one mutable adjacency index per configured forward-facing
# relationship member so recursive minimum pruning can remove documents without
# rerunning resolvers inside the prune phase.
class NormalGraph
	# Builds one mutable graph from one resolved session.
	def initialize(session:)
		@session = session
		@documents_by_collection = Hash.new { |hash, key| hash[key] = {} }
		@outgoing = Hash.new { |hash, key| hash[key] = {} }
		@incoming = Hash.new { |hash, key| hash[key] = {} }
		@source_members = Hash.new { |hash, key| hash[key] = {} }
		@target_members = Hash.new { |hash, key| hash[key] = {} }
		register_documents!
		register_edges!
	end

	# Returns every currently active document for one collection.
	def documents_for(collection)
		@documents_by_collection[collection].values
	end

	# Returns the neighbour documents for one configured relationship member.
	def neighbour_documents_for_member(member:, document:, inverse:)
		key = [member.sequence, document.object_id]
		(inverse ? @incoming[key] : @outgoing[key]).values
	end

	# Removes one document and every adjacent edge from the graph.
	def remove_document(document)
		collection_documents = @documents_by_collection[document.collection.label]
		return false unless collection_documents.delete(document.object_id)

		remove_source_edges(document)
		remove_target_edges(document)
		true
	end

	private

	# Registers every active document up front so zero-link documents still prune.
	def register_documents!
		@session.configuration.collections.each do |collection|
			@session.documents_for(collection).each do |document|
				@documents_by_collection[collection][document.object_id] = document
			end
		end
	end

	# Registers one deduplicated edge for every resolved forward-facing member.
	def register_edges!
		@session.configuration.configured_relationships.select(&:normal?).each do |member|
			@session.documents_for(member.from_collection).each do |document|
				state = @session.relationship_state(document, member.to_collection)
				next unless state

				state.current_link_entries.each_with_object({}) do |entry, unique_targets|
					target_document = entry.fetch(:document)
					unique_targets[target_document.object_id] ||= target_document
				end.each_value do |target_document|
					add_edge(member: member, source_document: document, target_document: target_document)
				end
			end
		end
	end

	# Stores one edge in both the forward and reverse adjacency indices.
	def add_edge(member:, source_document:, target_document:)
		@outgoing[[member.sequence, source_document.object_id]][target_document.object_id] = target_document
		@incoming[[member.sequence, target_document.object_id]][source_document.object_id] = source_document
		@source_members[source_document.object_id][member.sequence] = true
		@target_members[target_document.object_id][member.sequence] = true
	end

	# Removes every outgoing edge for one pruned source document.
	def remove_source_edges(document)
		member_sequences = @source_members.delete(document.object_id)&.keys || []
		member_sequences.each do |member_sequence|
			target_documents = @outgoing.delete([member_sequence, document.object_id]) || {}
			target_documents.each_key do |target_document_id|
				incoming_sources = @incoming[[member_sequence, target_document_id]]
				next unless incoming_sources

				incoming_sources.delete(document.object_id)
				@incoming.delete([member_sequence, target_document_id]) if incoming_sources.empty?
			end
		end
	end

	# Removes every incoming edge for one pruned target document.
	def remove_target_edges(document)
		member_sequences = @target_members.delete(document.object_id)&.keys || []
		member_sequences.each do |member_sequence|
			source_documents = @incoming.delete([member_sequence, document.object_id]) || {}
			source_documents.each_key do |source_document_id|
				outgoing_targets = @outgoing[[member_sequence, source_document_id]]
				next unless outgoing_targets

				outgoing_targets.delete(document.object_id)
				@outgoing.delete([member_sequence, source_document_id]) if outgoing_targets.empty?
			end
		end
	end
end

end
end

end
end
