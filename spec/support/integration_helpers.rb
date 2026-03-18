# frozen_string_literal: true

require 'yaml'

# Shared helpers for the integration suite.
#
# These helpers keep the suite focused on behaviour by centralising the Jekyll
# site scaffolding and the temporary resolver definitions used in examples.
module RelationshipsIntegrationHelpers

	# Builds one Markdown document with YAML frontmatter.
	def render_document(frontmatter = {}, body = 'Body')
		yaml = frontmatter.to_yaml.sub(/\A---\s*\n?/, '').sub(/\.\.\.\s*\n?\z/, '')
		"---\n#{yaml}---\n#{body}\n"
	end

	# Builds one collection document file tree for the harness.
	def collection_document(collection, name, frontmatter = {}, body = 'Body')
		{
			"_#{collection}" => {
				"#{name}.md" => render_document(frontmatter, body)
			}
		}
	end

	# Builds many collection documents at once.
	def collection_documents(collection, documents)
		{
			"_#{collection}" => documents.each_with_object({}) do |(name, specification), files|
				frontmatter = extract_document_frontmatter(specification)
				body = extract_document_body(specification)
				files["#{name}.md"] = render_document(frontmatter, body)
			end
		}
	end

	# Merges file trees into one site file hash with a default layout.
	def relationship_site_files(*file_hashes)
		Array(file_hashes).flatten.compact.reduce(
			{
				'_layouts' => {
					'default.html' => '{{ content }}'
				}
			}
		) do |merged, file_hash|
			jekyll_merge(merged, file_hash)
		end
	end

	# Builds one complete Jekyll config hash for a relationships site.
	def relationship_site_config(collections:, relationships:, extra: {})
		base_config = {
			'collections' => collections.each_with_object({}) do |collection, defined_collections|
				defined_collections[collection] = { 'output' => true }
			end,
			'relationships' => relationships
		}
		jekyll_merge(base_config, extra)
	end

	# Creates a reusable blueprint for one relationships test site.
	def relationship_blueprint(collections:, relationships:, files:, extra: {})
		jekyll_blueprint(
			config: relationship_site_config(collections: collections, relationships: relationships, extra: extra),
			files: files
		)
	end

	# Builds one relationships test site and yields the built site plus files.
	def build_relationship_site(collections:, relationships:, files:, extra: {}, &block)
		jekyll_build(
			relationship_blueprint(
				collections: collections,
				relationships: relationships,
				files: files,
				extra: extra
			),
			&block
		)
	end

	# Finds one document in a collection by basename.
	def document_for(site, collection, basename)
		site.collections.fetch(collection).docs.find { |document| document.basename_without_ext == basename }
	end

	# Extracts ordered reference ids from an array or singular reference.
	def reference_ids(references, key = 'id')
		normalise_references(references).map { |reference| reference.fetch(key) }
	end

	# Extracts one property from each normalised reference in order.
	def reference_values(references, property)
		normalise_references(references).map { |reference| reference.fetch(property) }
	end

	# Defines one temporary resolver class for the current example.
	def define_resolver(name, from:, to:, &block)
		resolver_class = Class.new(Jekyll::Plugins::Relationships::Resolvers::Base)
		resolver_class.from(from)
		resolver_class.to(to)
		resolver_class.class_eval(&block) if block
		stub_const("Jekyll::Plugins::Relationships::Resolvers::#{name}", resolver_class)
	end

	private

	# Normalises nil, singular, and array reference values into an array.
	def normalise_references(references)
		return [] if references.nil?
		return references if references.is_a?(Array)

		[references]
	end

	# Extracts frontmatter from a shorthand or explicit document definition.
	def extract_document_frontmatter(specification)
		return specification unless structured_document_specification?(specification)

		specification[:frontmatter] || specification['frontmatter'] || {}
	end

	# Extracts body text from a shorthand or explicit document definition.
	def extract_document_body(specification)
		return 'Body' unless structured_document_specification?(specification)

		specification[:body] || specification['body'] || 'Body'
	end

	# Returns true when one document specification uses explicit keys.
	def structured_document_specification?(specification)
		specification.is_a?(Hash) && (
			specification.key?(:frontmatter) ||
			specification.key?('frontmatter') ||
			specification.key?(:body) ||
			specification.key?('body')
		)
	end
end

RSpec.configure do |config|
	config.include RelationshipsIntegrationHelpers

	config.around do |example|
		original_registry = Jekyll::Plugins::Relationships::Resolvers::Base.registered_subclasses.dup
		example.run
		Jekyll::Plugins::Relationships::Resolvers::Base.instance_variable_set(:@registered_subclasses, original_registry)
	end
end
