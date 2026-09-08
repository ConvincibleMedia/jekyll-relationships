# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships
module Trees

# Builds every tree edge declared by the configuration.
#
# Frontmatter-driven and URL-driven tree discovery live here so the graph class
# can focus on storing edges and answering ancestry queries.
class EdgeBuilder
	# Builds one edge builder for the current graph.
	def initialize(graph:, configuration:, registry:, data_path:, debug_logger:)
		@graph = graph
		@configuration = configuration
		@registry = registry
		@data_path = data_path
		@debug_logger = debug_logger
		@string_array = Jekyll::Plugins::Relationships::Support::StringArray.new
	end

	# Builds every configured tree edge.
	def build!
		build_frontmatter_edges
		build_url_edges
	end

	private

	# Reads all declared parent and child references from frontmatter.
	def build_frontmatter_edges
		@configuration.tree_relationships.each do |definition|
			definition.parent_child_pairs.each do |parent_collection, child_collection|
				read_parent_references(
					definition: definition,
					parent_collection: parent_collection,
					child_collection: child_collection
				)
				read_child_references(
					definition: definition,
					parent_collection: parent_collection,
					child_collection: child_collection
				)
			end
		end
	end

	# Reads parent references from child documents.
	def read_parent_references(definition:, parent_collection:, child_collection:)
		path_configuration = definition.tree_settings.frontmatter

		@graph.documents_for(child_collection).each do |child_document|
			path_configuration.parent_input_paths(max_parents: definition.tree_settings.max_parents).each do |path|
				parse_references(@data_path.read(child_document.data, path), definition: definition, document: child_document).each do |reference|
					parent_document = resolve_reference(reference: reference, definition: definition, referring_document: child_document)
					next unless parent_document
					next unless parent_document.collection.label == parent_collection

					@debug_logger.tree_event(
						document: child_document,
						definition: definition,
						area: 'trees',
						event: 'tree_reference_resolved',
						details: {
							source: "frontmatter #{path}",
							reference: reference.metadata.merge('key' => reference.key, 'collection' => reference.collection),
							target: parent_document
						}
					)

					@graph.add_edge(
						parent_document: parent_document,
						child_document: child_document,
						tree_settings: definition.tree_settings,
						definition: definition,
						source_description: "frontmatter #{path}"
					)
				end
			end
		end
	end

	# Reads child references from parent documents.
	def read_child_references(definition:, parent_collection:, child_collection:)
		path_configuration = definition.tree_settings.frontmatter

		@graph.documents_for(parent_collection).each do |parent_document|
			path_configuration.child_input_paths(max_children: definition.tree_settings.max_children).each do |path|
				parse_references(@data_path.read(parent_document.data, path), definition: definition, document: parent_document).each do |reference|
					child_document = resolve_reference(reference: reference, definition: definition, referring_document: parent_document)
					next unless child_document
					next unless child_document.collection.label == child_collection

					@debug_logger.tree_event(
						document: parent_document,
						definition: definition,
						area: 'trees',
						event: 'tree_reference_resolved',
						details: {
							source: "frontmatter #{path}",
							reference: reference.metadata.merge('key' => reference.key, 'collection' => reference.collection),
							target: child_document
						}
					)

					@graph.add_edge(
						parent_document: parent_document,
						child_document: child_document,
						tree_settings: definition.tree_settings,
						definition: definition,
						source_description: "frontmatter #{path}"
					)
				end
			end
		end
	end

	# Adds URL-derived parent-child edges.
	def build_url_edges
		url_index = build_url_index
		@configuration.tree_relationships.each do |definition|
			next unless definition.tree_settings.url?

			definition.parent_child_pairs.each do |parent_collection, child_collection|
				@graph.documents_for(child_collection).each do |child_document|
					parts = normalised_url_parts(child_document)
					next if parts.length <= 1

					parent_parts = parts[0...-1]
					parents = fetch_nested(url_index, parent_collection, parent_parts)
					next unless parents

					parents.select { |parent_document| same_scope?(first_document: child_document, second_document: parent_document, definition: definition) }.each do |parent_document|
						@graph.add_edge(
							parent_document: parent_document,
							child_document: child_document,
							tree_settings: definition.tree_settings,
							definition: definition,
							source_description: 'url'
						)
					end
				end
			end
		end
	end

	# Builds a lookup from collection and URL parts to documents.
	def build_url_index
		@graph.tree_documents.each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |document, index|
			collection = document.collection.label
			parts = normalised_url_parts(document)
			index[collection][parts] ||= []
			index[collection][parts] << document
		end
	end

	# Normalises one document URL into path segments.
	def normalised_url_parts(document)
		document.url.to_s.sub(%r{\A/+}, '').sub(%r{/+index\.html\z}, '').sub(%r{/+\z}, '').split('/').reject(&:empty?)
	end

	# Parses one tree frontmatter value into parsed references.
	def parse_references(value, definition:, document:)
		@string_array.interpret(value, split: -1, flatten: true).map do |entry|
			@configuration.reference_template.parse(
				entry,
				context: "Relationship `#{definition.from_collection} -> #{definition.to_collection}` reference on document `#{document.relative_path}`"
			)
		end.compact
	end

	# Resolves one parsed reference to a real document.
	def resolve_reference(reference:, definition:, referring_document:)
		relationship = "#{definition.from_collection} -> #{definition.to_collection}"
		effective_scope = @registry.effective_scope_for(
			reference_scope: reference.scope,
			referring_document: referring_document,
			scope_fields: definition.scope_fields,
			relationship: relationship
		)
		if reference.document?
			@registry.validate_scope_match!(
				document: reference.page,
				scope: effective_scope,
				scope_fields: definition.scope_fields,
				relationship: relationship,
				referring_document: referring_document
			)
			return reference.page
		end

		collection = reference.collection.to_s unless reference.collection.nil?
		@registry.lookup(
			key: reference.key,
			primary_path: definition.primary_path,
			collection: collection,
			scope_fields: definition.scope_fields,
			scope: effective_scope,
			relationship: relationship,
			referring_document: referring_document
		)
	end

	# Returns true when two URL-selected documents share the definition's complete scope.
	def same_scope?(first_document:, second_document:, definition:)
		return true if definition.scope_fields.empty?

		relationship = "#{definition.from_collection} -> #{definition.to_collection}"
		@registry.scope_for(first_document, scope_fields: definition.scope_fields, relationship: relationship) ==
			@registry.scope_for(second_document, scope_fields: definition.scope_fields, relationship: relationship)
	end

	# Reads one nested hash value without creating a default entry.
	def fetch_nested(hash, first_key, second_key)
		first_hash = hash[first_key]
		return nil unless first_hash

		first_hash[second_key]
	end
end

end
end

end
end
