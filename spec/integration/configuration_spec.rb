# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'relationships configuration' do
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

		files = relationship_site_files(
			collection_document('products', 'alpha', {
				'links' => {
					'products' => ['products/beta']
				}
			}),
			collection_document('products', 'beta')
		)

		build_relationship_site(collections: %w[products], relationships: relationships, files: files) do |site, _files|
			product = document_for(site, 'products', 'alpha')
			expect(reference_ids(product.data.fetch('links').fetch('products'))).to eq(['products/beta'])
		end
	end

	it 'expands the others keyword across all other source collections' do
		relationships = {
			'frontmatter' => {
				'base' => 'data',
				'foreign' => 'links'
			},
			'relationships' => [
				{ 'from' => 'products, categories', 'to' => 'others' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'alpha', {
				'data' => {
					'links' => ['categories/one']
				}
			}),
			collection_document('categories', 'one', {
				'data' => {
					'links' => ['products/alpha']
				}
			})
		)

		build_relationship_site(collections: %w[products categories], relationships: relationships, files: files) do |site, _files|
			product = document_for(site, 'products', 'alpha')
			category = document_for(site, 'categories', 'one')

			expect(reference_ids(product.data.fetch('data').fetch('links'))).to eq(['categories/one'])
			expect(reference_ids(category.data.fetch('data').fetch('links'))).to eq(['products/alpha'])
		end
	end

	it 'expands the all keyword to include both self and the other collections' do
		relationships = {
			'frontmatter' => {
				'base' => 'data',
				'foreign' => 'refs.<collection>'
			},
			'relationships' => [
				{ 'from' => 'products, categories', 'to' => 'all' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'alpha', {
				'data' => {
					'refs' => {
						'products' => ['products/beta'],
						'categories' => ['categories/one']
					}
				}
			}),
			collection_document('products', 'beta'),
			collection_document('categories', 'one')
		)

		build_relationship_site(collections: %w[products categories], relationships: relationships, files: files) do |site, _files|
			product = document_for(site, 'products', 'alpha')

			expect(reference_ids(product.data.fetch('data').fetch('refs').fetch('products'))).to eq(['products/beta'])
			expect(reference_ids(product.data.fetch('data').fetch('refs').fetch('categories'))).to eq(['categories/one'])
		end
	end

	it 'applies relationship-level and target-level frontmatter overrides in precedence order' do
		relationships = {
			'frontmatter' => {
				'base' => 'data',
				'foreign' => 'refs.<collection>'
			},
			'relationships' => [
				{
					'from' => 'projects',
					'to' => [
						'services',
						{
							'collection' => 'deliverables',
							'frontmatter' => {
								'foreign' => 'custom.deliverables'
							}
						}
					],
					'frontmatter' => {
						'base' => 'meta'
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'meta' => {
					'refs' => {
						'services' => ['services/design']
					},
					'custom' => {
						'deliverables' => ['deliverables/site-map']
					}
				}
			}),
			collection_document('services', 'design'),
			collection_document('deliverables', 'site-map')
		)

		build_relationship_site(collections: %w[projects services deliverables], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')

			expect(reference_ids(project.data.fetch('meta').fetch('refs').fetch('services'))).to eq(['services/design'])
			expect(reference_ids(project.data.fetch('meta').fetch('custom').fetch('deliverables'))).to eq(['deliverables/site-map'])
		end
	end

	it 'supports custom reference template property names' do
		relationships = {
			'references' => {
				'slug' => '<key>',
				'bucket' => '<collection>',
				'entry' => '<page>'
			},
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'relationships' => {
					'services' => ['services/design']
				}
			}),
			collection_document('services', 'design')
		)

		build_relationship_site(collections: %w[projects services], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			reference = project.data.fetch('relationships').fetch('services').first

			expect(reference.keys).to contain_exactly('slug', 'bucket', 'entry')
			expect(reference.fetch('slug')).to eq('services/design')
			expect(reference.fetch('bucket')).to eq('services')
			expect(reference.fetch('entry')).to be_a(Jekyll::Document)
		end
	end

	it 'rejects reference config nested under frontmatter' do
		relationships = {
			'frontmatter' => {
				'references' => {
					'slug' => '<key>'
				}
			},
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha'),
			collection_document('services', 'design')
		)

		expect do
			build_relationship_site(collections: %w[projects services], relationships: relationships, files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /relationships\.references.*frontmatter/i)
	end

	it 'resolves key-only references when primary keys are unique site-wide' do
		relationships = {
			'frontmatter' => {
				'base' => '',
				'primary' => 'id',
				'foreign' => 'links'
			},
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'services, clients' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'id' => 'project-alpha',
				'links' => ['service-design', 'client-acme']
			}),
			collection_document('services', 'design', { 'id' => 'service-design' }),
			collection_document('clients', 'acme', { 'id' => 'client-acme' })
		)

		build_relationship_site(collections: %w[projects services clients], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			links = project.data.fetch('links')

			expect(reference_ids(links)).to eq(['service-design', 'client-acme'])
			expect(links.map { |reference| reference.fetch('collection') }).to eq(%w[services clients])
		end
	end

	it 'raises when a key-only reference is ambiguous across the site' do
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

		files = relationship_site_files(
			collection_document('products', 'alpha', {
				'id' => 'product-alpha',
				'links' => ['shared']
			}),
			collection_document('categories', 'one', { 'id' => 'shared' }),
			collection_document('tags', 'one', { 'id' => 'shared' })
		)

		expect do
			build_relationship_site(collections: %w[products categories tags], relationships: relationships, files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /ambiguous/i)
	end

	it 'raises when primary keys are duplicated within a collection' do
		relationships = {
			'frontmatter' => {
				'base' => '',
				'primary' => 'id'
			},
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', { 'id' => 'project-alpha' }),
			collection_document('services', 'design', { 'id' => 'shared' }),
			collection_document('services', 'build', { 'id' => 'shared' })
		)

		expect do
			build_relationship_site(collections: %w[projects services], relationships: relationships, files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /duplicated within collection/i)
	end

	it 'rejects duplicate and clashing relationship definitions' do
		relationships = {
			'relationships' => [
				{ 'from' => 'products', 'to' => 'services', 'mode' => 'bidirectional' },
				{ 'from' => 'services', 'to' => 'products' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'alpha'),
			collection_document('services', 'design')
		)

		expect do
			build_relationship_site(collections: %w[products services], relationships: relationships, files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /duplicate|clashing/i)
	end

	it 'rejects unsupported relationship modes' do
		relationships = {
			'relationships' => [
				{ 'from' => 'products', 'to' => 'services', 'mode' => 'sideways' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'alpha'),
			collection_document('services', 'design')
		)

		expect do
			build_relationship_site(collections: %w[products services], relationships: relationships, files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /unsupported relationship mode/i)
	end
end
