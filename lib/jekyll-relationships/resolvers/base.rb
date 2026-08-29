# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships
module Resolvers

# Declares or reads the global default persistence mode for resolver link calls.
#
# Resolver classes can override this locally with their own `persist true/false`
# declaration. When left unset on the class, `link(...)` falls back to this
# module-wide default.
def self.persist(value = :__read__)
	return Base.global_persist_default if value == :__read__

	Base.global_persist_default = value
end

# Base class for custom relationship resolvers.
#
# Subclass this in `_plugins`, declare `from` and `to`, then implement
# `resolve` to add or remove links while the engine is resolving one concrete
# document-to-collection pair.
class Base

	@registered_subclasses = []
	@global_persist_default = false

	class << self
		attr_reader :from_definition, :to_definition

		# Tracks subclasses while their class bodies are still being declared.
		def inherited(subclass)
			Base.remove_registered_subclass(subclass: subclass)
			super
		end

		# Declares or reads the resolver's `from` selector.
		def from(value = nil)
			unless value.nil?
				@from_definition = value
				Base.refresh_registered_subclass(subclass: self)
			end
			@from_definition
		end

		# Declares or reads the resolver's `to` selector.
		def to(value = nil)
			unless value.nil?
				@to_definition = value
				Base.refresh_registered_subclass(subclass: self)
			end
			@to_definition
		end

		# Declares or reads the default persistence mode for this resolver class.
		def persist(value = :__read__)
			unless value == :__read__
				@persist_default = normalise_persist_default(
					value,
					context: "#{name || self}.persist"
				)
			end
			return @persist_default unless @persist_default.nil?
			return superclass.persist if self != Base && superclass.respond_to?(:persist)

			global_persist_default
		end

		# Returns the module-wide fallback persistence mode.
		def global_persist_default
			return false unless instance_variable_defined?(:@global_persist_default)

			@global_persist_default
		end

		# Sets the module-wide fallback persistence mode.
		def global_persist_default=(value)
			@global_persist_default = normalise_persist_default(
				value,
				context: 'Resolvers.persist'
			)
		end

		# Returns every resolver subclass whose `from` and `to` selectors are complete.
		def registered_subclasses
			@registered_subclasses ||= []
		end

		# Synchronises one resolver subclass with the shared registry after class-level declarations change.
		def refresh_registered_subclass(subclass:)
			remove_registered_subclass(subclass: subclass)
			return if subclass == Base
			return if subclass.from_definition.nil? || subclass.to_definition.nil?

			registered_subclasses << subclass
		end

		# Removes one resolver subclass from the shared registry while declaration is incomplete.
		def remove_registered_subclass(subclass:)
			registered_subclasses.delete(subclass)
		end

		private

		# Normalises one resolver persistence default to a strict boolean.
		def normalise_persist_default(value, context:)
			return value if value == true || value == false

			raise ConfigurationError, "`#{context}` must be true or false."
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
		result = if document == @document && target_collection == @to && @state.resolving?
						 @state.current_references
					 else
						 @engine.resolve_relationships(document, target_collection)
					 end
		debug_helper('resolver_relationships', {
			reference: reference,
			from: from,
			target_document: document,
			to: target_collection,
			result: result
		})
		result
	end

	# Returns the referenced document, resolving its outgoing pairs if needed.
	def document(reference = nil, from: nil)
		document = resolve_helper_document(reference, from)
		if document == @document
			debug_helper('resolver_document', {
				reference: reference,
				from: from,
				target_document: document
			})
			return document
		end

		@engine.resolve_document(document)
		debug_helper('resolver_document', {
			reference: reference,
			from: from,
			target_document: document
		})
		document
	end

	# Returns ancestors for one document reference.
	def ancestors(reference = nil, from: nil, min: 1, max: -1)
		document = resolve_helper_document(reference, from)
		result = @engine.tree_graph.ancestors_for(document, min: min, max: max)
		debug_helper('resolver_ancestors', {
			reference: reference,
			from: from,
			target_document: document,
			min: min,
			max: max,
			result: result
		})
		result
	end

	# Returns parents for one document reference.
	def parents(reference = nil, from: nil)
		ancestors(reference, from: from, min: 1, max: 1)
	end

	# Returns descendants for one document reference.
	def descendants(reference = nil, from: nil, min: 1, max: -1)
		document = resolve_helper_document(reference, from)
		result = @engine.tree_graph.descendants_for(document, min: min, max: max)
		debug_helper('resolver_descendants', {
			reference: reference,
			from: from,
			target_document: document,
			min: min,
			max: max,
			result: result
		})
		result
	end

	# Returns children for one document reference.
	def children(reference = nil, from: nil)
		descendants(reference, from: from, min: 1, max: 1)
	end

	# Adds one relationship from the current document to the target collection.
	#
	# When `persist` is true, the link may be restored in later rounds if the
	# resolver does not recreate it and both linked documents still survive.
	def link(target_reference, reference: nil, persist: nil)
		@state.link(
			target_reference,
			metadata: reference,
			origin: "resolver #{self.class.name || self.class}",
			persist: persist.nil? ? self.class.persist : persist
		)
	end

	# Removes one relationship, or all of them when no reference is given.
	def unlink(reference = nil)
		@state.unlink(
			reference,
			origin: "resolver #{self.class.name || self.class}"
		)
	end

	private

	# Resolves one resolver helper argument to a real document.
	def resolve_helper_document(reference, from_collection)
		return @document if reference.nil?

		@engine.resolve_reference_document(
			reference,
			primary_path: @state.definition.primary_path,
			scope_fields: @state.definition.scope_fields,
			referring_document: @document,
			relationship: "#{@state.definition.from_collection} -> #{@state.definition.to_collection}",
			collection_hint: from_collection
		)
	end

	# Emits one debug line for one resolver helper call when enabled.
	def debug_helper(event, details)
		@engine.debug_logger.relationship_event(
			document: @document,
			definition: @state.definition,
			area: 'resolvers',
			event: event,
			details: details
		)
	end
end

end
end

end
end
