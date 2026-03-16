# frozen_string_literal: true

require 'yaml'
require 'spec_helper'

RSpec.describe 'jekyll relationships integration' do

	# Restores the resolver registry after each example so test-specific
	# subclasses do not leak into later builds.
	around do |example|
		original_registry = Jekyll::Plugins::Relationships::Resolvers::Base.registered_subclasses.dup
		example.run
		Jekyll::Plugins::Relationships::Resolvers::Base.instance_variable_set(:@registered_subclasses, original_registry)
	end

	# Builds one rendered Markdown document string.
	def render_document(frontmatter = {}, body = 'Body')
		yaml = frontmatter.to_yaml.sub(/\A---\s*\n?/, '').sub(/\.\.\.\s*\n?\z/, '')
		"---\n#{yaml}---\n#{body}\n"
	end

	# Builds one collection document file hash for the harness.
	def collection_document(collection, name, frontmatter = {}, body = 'Body')
		{
			"_#{collection}" => {
				"#{name}.md" => render_document(frontmatter, body)
			}
		}
	end

	# Merges many file hashes into one site file tree.
	def site_files(*file_hashes)
		file_hashes.compact.reduce(
			{
				'_layouts' => {
					'default.html' => '{{ content }}'
				}
			}
		) do |merged, file_hash|
			jekyll_merge(merged, file_hash)
		end
	end

	# Builds one site config with all requested collections enabled for output.
	def site_config(collections:, relationships:, extra: {})
		base_config = {
			'collections' => collections.each_with_object({}) do |collection, defined_collections|
				defined_collections[collection] = { 'output' => true }
			end,
			'relationships' => relationships
		}
		jekyll_merge(base_config, extra)
	end

	# Finds one document in a collection by basename.
	def document_for(site, collection, basename)
		site.collections.fetch(collection).docs.find { |document| document.basename_without_ext == basename }
	end

	# Extracts ordered keys from a reference array.
	def reference_keys(references, key = 'id')
		Array(references).map { |reference| reference.fetch(key) }
	end

	# Defines one temporary resolver class for the current example.
	def define_resolver(name, from:, to:, &block)
		resolver_class = Class.new(Jekyll::Plugins::Relationships::Resolvers::Base)
		resolver_class.from(from)
		resolver_class.to(to)
		resolver_class.class_eval(&block) if block
		stub_const("Jekyll::Plugins::Relationships::Resolvers::#{name}", resolver_class)
	end

	it 'resolves default one-way links and upgrades references into hashes' do
		relationships = {
			'relationships' => [
				{ 'from' => 'products', 'to' => 'categories' }
			]
		}

		files = site_files(
			collection_document('products', 'shoes', {
				'relationships' => {
					'categories' => ['categories/trainers']
				}
			}),
			collection_document('categories', 'trainers')
		)

		jekyll_build(config: site_config(collections: %w[products categories], relationships: relationships), files: files) do |site, _files|
			product = document_for(site, 'products', 'shoes')
			category = document_for(site, 'categories', 'trainers')
			references = product.data.fetch('relationships').fetch('categories')

			expect(references.length).to eq(1)
			expect(references.first.fetch('id')).to eq('categories/trainers')
			expect(references.first.fetch('collection')).to eq('categories')
			expect(references.first.fetch('page')).to eq(category)
			expect(category.data.fetch('relationships', {})).not_to have_key('products')
		end
	end

	it 'mirrors bidirectional links onto the implied reverse relationship' do
		relationships = {
			'relationships' => [
				{ 'from' => 'products', 'to' => 'services', 'mode' => 'bidirectional' }
			]
		}

		files = site_files(
			collection_document('products', 'alpha', {
				'relationships' => {
					'services' => ['services/design']
				}
			}),
			collection_document('services', 'design')
		)

		jekyll_build(config: site_config(collections: %w[products services], relationships: relationships), files: files) do |site, _files|
			service = document_for(site, 'services', 'design')
			expect(reference_keys(service.data.fetch('relationships').fetch('products'))).to eq(['products/alpha'])
		end
	end

	it 'supports overridden keywords for self relationships and collection placeholders' do
		relationships = {
			'keywords' => {
				'self' => 'itself',
				'collection' => 'bucket'
			},
			'frontmatter' => {
				'base' => 'links',
				'foreign' => '<bucket>'
			},
			'relationships' => [
				{ 'from' => 'products', 'to' => 'itself' }
			]
		}

		files = site_files(
			collection_document('products', 'alpha', {
				'links' => {
					'products' => ['products/beta']
				}
			}),
			collection_document('products', 'beta')
		)

		jekyll_build(config: site_config(collections: %w[products], relationships: relationships), files: files) do |site, _files|
			product = document_for(site, 'products', 'alpha')
			expect(reference_keys(product.data.fetch('links').fetch('products'))).to eq(['products/beta'])
		end
	end

	it 'uses global key-only lookup and raises when a key is ambiguous site-wide' do
		relationships = {
			'frontmatter' => {
				'base' => '',
				'primary' => 'id',
				'foreign' => 'links'
			},
			'relationships' => [
				{ 'from' => 'products', 'to' => 'categories, tags' }
			]
		}

		files = site_files(
			collection_document('products', 'alpha', {
				'id' => 'product-alpha',
				'links' => ['shared']
			}),
			collection_document('categories', 'one', { 'id' => 'shared' }),
			collection_document('tags', 'one', { 'id' => 'shared' })
		)

		expect do
			jekyll_build(config: site_config(collections: %w[products categories tags], relationships: relationships), files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /ambiguous/)
	end

	it 'upgrades every input path but rewrites the final link set only onto the first foreign path' do
		define_resolver('FirstPathRewriteResolver', from: 'products', to: 'categories') do

			# Touches `document` and `relationships` on the current state to prove
			# both helpers can operate without forcing recursive self-resolution.
			def resolve
				document
				link('categories/extra', reference: { 'source' => 'resolver' }) if relationships.length == 2
			end
		end

		relationships = {
			'frontmatter' => {
				'base' => 'data',
				'foreign' => ['primary.<collection>', 'secondary']
			},
			'relationships' => [
				{ 'from' => 'products', 'to' => 'categories' }
			]
		}

		files = site_files(
			collection_document('products', 'alpha', {
				'data' => {
					'primary' => {
						'categories' => ['categories/one']
					},
					'secondary' => ['categories/two']
				}
			}),
			collection_document('categories', 'one'),
			collection_document('categories', 'two'),
			collection_document('categories', 'extra')
		)

		jekyll_build(config: site_config(collections: %w[products categories], relationships: relationships), files: files) do |site, _files|
			product = document_for(site, 'products', 'alpha')
			data = product.data.fetch('data')

			expect(reference_keys(data.fetch('primary').fetch('categories'))).to eq([
				'categories/one',
				'categories/two',
				'categories/extra'
			])
			expect(reference_keys(data.fetch('secondary'))).to eq(['categories/two'])
		end
	end

	it 'writes the final link set to frontmatter.output when one is configured' do
		define_resolver('SeparateOutputResolver', from: 'products', to: 'categories') do

			# Adds one extra relationship so the output path clearly differs from
			# the upgraded source paths.
			def resolve
				link('categories/extra') if relationships.length == 2
			end
		end

		relationships = {
			'frontmatter' => {
				'base' => 'data',
				'foreign' => ['primary.<collection>', 'secondary'],
				'output' => 'resolved.categories'
			},
			'relationships' => [
				{ 'from' => 'products', 'to' => 'categories' }
			]
		}

		files = site_files(
			collection_document('products', 'alpha', {
				'data' => {
					'primary' => {
						'categories' => ['categories/one']
					},
					'secondary' => ['categories/two']
				}
			}),
			collection_document('categories', 'one'),
			collection_document('categories', 'two'),
			collection_document('categories', 'extra')
		)

		jekyll_build(config: site_config(collections: %w[products categories], relationships: relationships), files: files) do |site, _files|
			product = document_for(site, 'products', 'alpha')
			data = product.data.fetch('data')

			expect(reference_keys(data.fetch('primary').fetch('categories'))).to eq(['categories/one'])
			expect(reference_keys(data.fetch('secondary'))).to eq(['categories/two'])
			expect(reference_keys(data.fetch('resolved').fetch('categories'))).to eq([
				'categories/one',
				'categories/two',
				'categories/extra'
			])
		end
	end

	it 'builds tree relationships and calculates shortest ancestor distances' do
		relationships = {
			'relationships' => [
				{ 'from' => 'deliverables', 'to' => 'self', 'mode' => 'parent' }
			]
		}

		files = site_files(
			collection_document('deliverables', 'root'),
			collection_document('deliverables', 'branch_a', {
				'relationships' => {
					'parent' => 'deliverables/root'
				}
			}),
			collection_document('deliverables', 'branch_b', {
				'relationships' => {
					'parent' => 'deliverables/root'
				}
			}),
			collection_document('deliverables', 'leaf', {
				'relationships' => {
					'parents' => ['deliverables/branch_a', 'deliverables/branch_b']
				}
			})
		)

		jekyll_build(config: site_config(collections: %w[deliverables], relationships: relationships), files: files) do |site, _files|
			leaf = document_for(site, 'deliverables', 'leaf')
			ancestors = leaf.data.fetch('relationships').fetch('ancestors')

			expect(reference_keys(leaf.data.fetch('relationships').fetch('parents'))).to eq([
				'deliverables/branch_a',
				'deliverables/branch_b'
			])
			expect(ancestors.map { |reference| [reference.fetch('id'), reference.fetch('distance')] }).to eq([
				['deliverables/leaf', 0],
				['deliverables/branch_a', 1],
				['deliverables/branch_b', 1],
				['deliverables/root', 2]
			])
		end
	end

	it 'supports singular tree outputs when max parents and children are one' do
		relationships = {
			'tree' => {
				'max' => {
					'parents' => 1,
					'children' => 1
				}
			},
			'relationships' => [
				{ 'from' => 'categories', 'to' => 'self', 'mode' => 'parent' }
			]
		}

		files = site_files(
			collection_document('categories', 'root', {
				'relationships' => {
					'child' => 'categories/leaf'
				}
			}),
			collection_document('categories', 'leaf')
		)

		jekyll_build(config: site_config(collections: %w[categories], relationships: relationships), files: files) do |site, _files|
			root = document_for(site, 'categories', 'root')
			leaf = document_for(site, 'categories', 'leaf')

			expect(root.data.fetch('relationships').fetch('child').fetch('id')).to eq('categories/leaf')
			expect(leaf.data.fetch('relationships').fetch('parent').fetch('id')).to eq('categories/root')
			expect(leaf.data.fetch('relationships').fetch('ancestors').first.fetch('id')).to eq('categories/leaf')
		end
	end

	it 'infers tree parents from URLs when URL mode is enabled' do
		relationships = {
			'tree' => {
				'url' => true
			},
			'relationships' => [
				{ 'from' => 'pages', 'to' => 'self', 'mode' => 'parent' }
			]
		}

		files = site_files(
			collection_document('pages', 'guides', {
				'permalink' => '/guides/'
			}),
			collection_document('pages', 'intro', {
				'permalink' => '/guides/intro/'
			})
		)

		jekyll_build(config: site_config(collections: %w[pages], relationships: relationships), files: files) do |site, _files|
			intro = document_for(site, 'pages', 'intro')
			expect(reference_keys(intro.data.fetch('relationships').fetch('parents'))).to eq(['pages/guides'])
		end
	end

	it 'lets resolvers recurse into linked items and traverse tree ancestry' do
		define_resolver('ProjectServicesResolver', from: 'projects', to: 'services') do

			# Derives project services from its deliverables and all ancestors.
			def resolve
				relationships(to: 'deliverables').each do |deliverable|
					ancestors(deliverable, min: 0).each do |ancestor|
						relationships(ancestor, to: 'services').each do |service|
							link(service, reference: { 'distance' => ancestor.fetch('distance') })
						end
					end
				end
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'deliverables', 'to' => 'self', 'mode' => 'parent' },
				{ 'from' => 'deliverables', 'to' => 'services' },
				{ 'from' => 'projects', 'to' => 'deliverables' },
				{ 'from' => 'projects', 'to' => 'services' }
			]
		}

		files = site_files(
			collection_document('deliverables', 'root', {
				'relationships' => {
					'services' => ['services/design']
				}
			}),
			collection_document('deliverables', 'child', {
				'relationships' => {
					'parent' => 'deliverables/root'
				}
			}),
			collection_document('projects', 'alpha', {
				'relationships' => {
					'deliverables' => ['deliverables/child']
				}
			}),
			collection_document('services', 'design')
		)

		jekyll_build(config: site_config(collections: %w[deliverables projects services], relationships: relationships), files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			services = project.data.fetch('relationships').fetch('services')

			expect(reference_keys(services)).to eq(['services/design'])
			expect(services.first.fetch('distance')).to eq(1)
		end
	end

	it 'rejects duplicate and clashing relationship definitions' do
		relationships = {
			'relationships' => [
				{ 'from' => 'products', 'to' => 'services', 'mode' => 'bidirectional' },
				{ 'from' => 'services', 'to' => 'products' }
			]
		}

		files = site_files(
			collection_document('products', 'alpha'),
			collection_document('services', 'design')
		)

		expect do
			jekyll_build(config: site_config(collections: %w[products services], relationships: relationships), files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /Duplicate|clashing/)
	end
end
