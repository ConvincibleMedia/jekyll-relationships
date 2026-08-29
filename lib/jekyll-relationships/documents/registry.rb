# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships
module Documents

# Indexes participating documents by collection, primary key, and optional complete scope.
#
# Indices are built lazily per complete identity scheme so relationship definitions can
# use different primary and scope paths without rebuilding unrelated lookups.
class Registry

	# Builds the registry over the collections used by the configuration.
	def initialize(site:, collections:)
		@site = site
		@collections = collections
		@indices_by_identity = {}
		@data_path = Jekyll::Plugins::Relationships::Support::DataPath.new
	end

	# Returns true when the document belongs to one of the tracked collections.
	def participating?(document)
		@collections.include?(collection_label(document))
	end

	# Returns the collection label for one document.
	def collection_label(document)
		document.collection.label
	end

	# Returns all participating documents for one collection.
	def documents_for(collection)
		site_collection = @site.collections[collection]
		return [] unless site_collection

		site_collection.docs
	end

	# Ensures every configured relationship collection exists on the Jekyll site.
	def validate_collections!
		missing_collections = @collections.reject { |collection| @site.collections.key?(collection) }
		return if missing_collections.empty?

		raise ConfigurationError, "Relationship collections are not defined on the site: #{missing_collections.sort.join(', ')}."
	end

	# Builds every requested primary-key index so duplicates fail eagerly.
	def validate_primary_paths!(primary_paths:)
		Array(primary_paths).uniq.each do |primary_path|
			index_for(primary_path: primary_path, scope_fields: [])
		end
	end

	# Builds every requested identity index so missing scope values and duplicate identities fail eagerly.
	def validate_identity_schemes!(identity_schemes:)
		Array(identity_schemes).each do |scheme|
			index_for(
				primary_path: scheme.fetch(:primary_path),
				scope_fields: scheme.fetch(:scope_fields),
				collections: scheme.fetch(:collections),
				relationship: scheme.fetch(:relationships).join(', ')
			)
		end
	end

	# Computes the active primary key for one document and scheme.
	def key_for(document, primary_path:)
		if primary_path.nil?
			default_relative_key(document)
		else
			value = @data_path.read(document.data, primary_path)
			raise ResolutionError, "Document `#{document.relative_path}` is missing primary key path `#{primary_path}`." if value.nil?

			value.to_s
		end
	end

	# Reads and validates a document's complete scope for one configured identity scheme.
	def scope_for(document, scope_fields:, relationship: nil)
		return nil if scope_fields.empty?

		scope_fields.each_with_object({}) do |field, scope|
			value = @data_path.read(document.data, field.path)
			if value.nil?
				raise ResolutionError, "#{relationship_prefix(relationship)}document `#{document.relative_path}` is missing required scope field `#{field.name}` at frontmatter path `#{field.path}`."
			end

			scope[field.name] = value
		end
	end

	# Resolves reference overrides over the referring document's scope and validates every configured field.
	def effective_scope_for(reference_scope:, referring_document:, scope_fields:, relationship: nil)
		return nil if scope_fields.empty? && (reference_scope.nil? || reference_scope.empty?)

		reference_scope ||= {}
		unless reference_scope.is_a?(Hash)
			raise ResolutionError, "#{relationship_prefix(relationship)}reference on document `#{referring_document.relative_path}` must provide scope as a hash."
		end

		configured_names = scope_fields.map(&:name)
		unknown_names = reference_scope.keys.map(&:to_s) - configured_names
		unless unknown_names.empty?
			raise ResolutionError, "#{relationship_prefix(relationship)}reference on document `#{referring_document.relative_path}` uses unconfigured scope field `#{unknown_names.first}`."
		end

		scope_fields.each_with_object({}) do |field, effective_scope|
			value = if hash_property?(reference_scope, field.name)
						 Jekyll::Plugins::Relationships::Support::FrontmatterPath.read_hash(reference_scope, field.name)
					 else
						 @data_path.read(referring_document.data, field.path)
					 end
			if value.nil?
				raise ResolutionError, "#{relationship_prefix(relationship)}reference on document `#{referring_document.relative_path}` has no effective value for scope field `#{field.name}`."
			end

			effective_scope[field.name] = value
		end
	end

	# Ensures one already-selected target contains and exactly matches an effective scope.
	def validate_scope_match!(document:, scope:, scope_fields:, relationship: nil, referring_document: nil)
		return nil if scope_fields.empty?

		target_scope = scope_for(document, scope_fields: scope_fields, relationship: relationship)
		scope_fields.each do |field|
			next if target_scope.fetch(field.name) == scope.fetch(field.name)

			raise ResolutionError, scope_mismatch_message(
				document: document,
				field: field,
				expected_value: scope.fetch(field.name),
				actual_value: target_scope.fetch(field.name),
				relationship: relationship,
				referring_document: referring_document
			)
		end

		target_scope
	end

	# Resolves one key and complete scope to a document, optionally constrained to a collection.
	def lookup(key:, primary_path:, collection: nil, scope_fields: [], scope: nil, relationship: nil, referring_document: nil)
		index = index_for(primary_path: primary_path, scope_fields: scope_fields, relationship: relationship)
		candidates = if collection
						 fetch_nested(index.fetch(:by_collection), collection, key.to_s) || []
					 else
						 index.fetch(:by_key).fetch(key.to_s, [])
					 end
		if candidates.empty?
			if collection
				raise ResolutionError, "#{relationship_prefix(relationship)}could not resolve key `#{key}` in collection `#{collection}`#{source_suffix(referring_document)}."
			end

			raise ResolutionError, "#{relationship_prefix(relationship)}could not resolve key-only reference `#{key}`#{source_suffix(referring_document)}."
		end

		matches = if scope_fields.empty?
					 candidates
				 else
					 candidates.select { |entry| entry.fetch(:scope) == scope }
				 end
		if matches.empty?
			raise_scope_mismatch!(
				candidates: candidates,
				scope: scope,
				scope_fields: scope_fields,
				relationship: relationship,
				referring_document: referring_document
			)
		end

		matched_documents = matches.map { |entry| entry.fetch(:document) }
		return matched_documents.first if collection

		return matched_documents.first if matched_documents.length == 1

		collections = matched_documents.map { |document| collection_label(document) }.uniq.sort.join(', ')
		raise ResolutionError, "#{relationship_prefix(relationship)}key-only reference `#{key}` is ambiguous across collections: #{collections}#{source_suffix(referring_document)}."
	end

	private

	# Returns or builds the index for one complete identity scheme.
	def index_for(primary_path:, scope_fields:, collections: nil, relationship: nil)
		signature = [primary_path.nil? ? '__relative_path__' : primary_path, scope_fields.map(&:signature)]
		@indices_by_identity[signature] ||= build_index(
			primary_path: primary_path,
			scope_fields: scope_fields,
			collections: collections || @collections,
			relationship: relationship
		)
	end

	# Builds the collection and global indices for one complete identity scheme.
	def build_index(primary_path:, scope_fields:, collections:, relationship: nil)
		by_collection = Hash.new { |hash, key| hash[key] = Hash.new { |nested_hash, nested_key| nested_hash[nested_key] = [] } }
		by_key = Hash.new { |hash, key| hash[key] = [] }

		collections.each do |collection|
			documents_for(collection).each do |document|
				key = key_for(document, primary_path: primary_path)
				scope = scope_for(document, scope_fields: scope_fields, relationship: relationship)
				existing_entry = by_collection[collection][key].find { |entry| entry.fetch(:scope) == scope }
				if existing_entry
					if scope_fields.empty?
						raise ResolutionError, "Primary key `#{key}` is duplicated within collection `#{collection}`."
					end

					raise ResolutionError, "#{relationship_prefix(relationship)}primary key `#{key}` is duplicated within collection `#{collection}` and scope #{scope.inspect} by documents `#{existing_entry.fetch(:document).relative_path}` and `#{document.relative_path}`."
				end

				entry = { document: document, scope: scope }
				by_collection[collection][key] << entry
				by_key[key] << entry
			end
		end

		{
			by_collection: by_collection,
			by_key: by_key
		}
	end

	# Reads one nested hash value without creating a default entry.
	def fetch_nested(hash, first_key, second_key)
		first_hash = hash[first_key]
		return nil unless first_hash

		first_hash[second_key]
	end

	# Raises a field-specific error when key candidates exist but none match the requested complete scope.
	def raise_scope_mismatch!(candidates:, scope:, scope_fields:, relationship:, referring_document:)
		candidate = candidates.first
		field = scope_fields.find do |configured_field|
			candidate.fetch(:scope).fetch(configured_field.name) != scope.fetch(configured_field.name)
		end
		raise ResolutionError, scope_mismatch_message(
			document: candidate.fetch(:document),
			field: field,
			expected_value: scope.fetch(field.name),
			actual_value: candidate.fetch(:scope).fetch(field.name),
			relationship: relationship,
			referring_document: referring_document
		)
	end

	# Builds one detailed exact-match failure for a configured scope field.
	def scope_mismatch_message(document:, field:, expected_value:, actual_value:, relationship:, referring_document:)
		"#{relationship_prefix(relationship)}target document `#{document.relative_path}` has scope field `#{field.name}` value `#{actual_value.inspect}`, not the required `#{expected_value.inspect}`#{source_suffix(referring_document)}."
	end

	# Returns true when one literal scope key exists in string or symbol form.
	def hash_property?(hash, property)
		hash.key?(property) || hash.key?(property.to_s) || hash.key?(property.to_s.to_sym)
	end

	# Prefixes an error with its concrete relationship where available.
	def relationship_prefix(relationship)
		return '' if relationship.nil? || relationship.to_s.empty?

		"Relationship `#{relationship}`: "
	end

	# Adds the referring document to lookup diagnostics where available.
	def source_suffix(document)
		return '' unless document

		" from document `#{document.relative_path}`"
	end

	# Implements the README's default relative-path key rule.
	def default_relative_key(document)
		document.relative_path.sub(/\A_/, '').sub(/#{Regexp.escape(document.extname)}\z/, '')
	end
end

end
end

end
end
