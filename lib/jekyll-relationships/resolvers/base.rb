# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships
module Resolvers

# Base class for custom relationship resolvers.
#
# Subclass this in `_plugins`, declare `from` and `to`, then implement
# `resolve` to add or remove links while the engine is resolving one concrete
# document-to-collection pair.
class Base

	@registered_subclasses = []

	class << self
		attr_reader :from_definition, :to_definition, :registered_subclasses

		# Tracks subclasses so the engine can discover them later.
		def inherited(subclass)
			@registered_subclasses ||= []
			@registered_subclasses << subclass
			super
		end

		# Declares or reads the resolver's `from` selector.
		def from(value = nil)
			@from_definition = value unless value.nil?
			@from_definition
		end

		# Declares or reads the resolver's `to` selector.
		def to(value = nil)
			@to_definition = value unless value.nil?
			@to_definition
		end

		# Returns every registered resolver subclass.
		def registered_subclasses
			@registered_subclasses ||= []
		end
	end

	# Builds one resolver instance for one resolving relationship state.
	def initialize(engine:, state:)
		@engine = engine
		@state = state
		@document = state.document
		@key = @engine.registry.key_for(@document, primary_path: state.definition.primary_path)
		@from = state.definition.from_collection
		@to = state.definition.to_collection
		@site = @engine.site
	end

	# Override this in subclasses to change relationship output.
	def resolve
		raise NotImplementedError, "#{self.class} must implement `resolve`."
	end

	# Returns current relationships for one document and target collection.
	def relationships(reference = nil, to: nil, from: nil)
		target_collection = to || @to
		document = resolve_helper_document(reference, from)
		if document == @document && target_collection == @to && @state.resolving?
			return @state.current_references
		end

		@engine.resolve_relationships(document, target_collection)
	end

	# Returns the referenced document, resolving its outgoing pairs if needed.
	def document(reference = nil, from: nil)
		document = resolve_helper_document(reference, from)
		return document if document == @document

		@engine.resolve_document(document)
		document
	end

	# Returns ancestors for one document reference.
	def ancestors(reference = nil, from: nil, min: 1, max: -1)
		document = resolve_helper_document(reference, from)
		@engine.tree_graph.ancestors_for(document, min: min, max: max)
	end

	# Returns parents for one document reference.
	def parents(reference = nil, from: nil)
		ancestors(reference, from: from, min: 1, max: 1)
	end

	# Returns descendants for one document reference.
	def descendants(reference = nil, from: nil, min: 1, max: -1)
		document = resolve_helper_document(reference, from)
		@engine.tree_graph.descendants_for(document, min: min, max: max)
	end

	# Returns children for one document reference.
	def children(reference = nil, from: nil)
		descendants(reference, from: from, min: 1, max: 1)
	end

	# Adds one relationship from the current document to the target collection.
	def link(target_reference, reference: nil)
		@state.link(target_reference, metadata: reference)
	end

	# Removes one relationship, or all of them when no reference is given.
	def unlink(reference = nil)
		@state.unlink(reference)
	end

	private

	# Resolves one resolver helper argument to a real document.
	def resolve_helper_document(reference, from_collection)
		return @document if reference.nil?

		@engine.resolve_reference_document(
			reference,
			primary_path: @state.definition.primary_path,
			collection_hint: from_collection
		)
	end
end

end
end

end
end
