# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'scoped primary-key resolution' do
	def scoped_relationships(overrides = {})
		jekyll_merge(
			{
				'frontmatter' => {
					'base' => '',
					'primary' => 'meta.id',
					'scope' => ['locale', 'meta.region'],
					'foreign' => 'relationships.<collection>'
				},
				'relationships' => [
					{ 'from' => 'pages', 'to' => 'self' }
				]
			},
			overrides
		)
	end

	def scoped_page(id:, locale:, region:, references: nil)
		frontmatter = {
			'meta' => {
				'id' => id,
				'region' => region
			},
			'locale' => locale
		}
		frontmatter['relationships'] = { 'pages' => references } unless references.nil?
		frontmatter
	end

	it 'inherits complete scope for string references and permits duplicate keys in different scopes' do
		files = relationship_site_files(
			collection_document('pages', 'source', scoped_page(id: 'A', locale: 'en', region: 'uk', references: 'B')),
			collection_document('pages', 'target-en', scoped_page(id: 'B', locale: 'en', region: 'uk')),
			collection_document('pages', 'target-fr', scoped_page(id: 'B', locale: 'fr', region: 'uk'))
		)

		build_relationship_site(collections: %w[pages], relationships: scoped_relationships, files: files) do |site, _files|
			reference = document_for(site, 'pages', 'source').data.fetch('relationships').fetch('pages').first

			expect(reference.fetch('id')).to eq('B')
			expect(reference.fetch('scope')).to eq('locale' => 'en', 'meta.region' => 'uk')
			expect(reference.fetch('page').basename_without_ext).to eq('target-en')
		end
	end

	it 'lets hash references override selected scope fields while inheriting omitted fields' do
		files = relationship_site_files(
			collection_document('pages', 'source', scoped_page(
				id: 'A',
				locale: 'en',
				region: 'uk',
				references: {
					'id' => 'B',
					'collection' => 'pages',
					'scope' => { 'locale' => 'fr' }
				}
			)),
			collection_document('pages', 'target-en', scoped_page(id: 'B', locale: 'en', region: 'uk')),
			collection_document('pages', 'target-fr', scoped_page(id: 'B', locale: 'fr', region: 'uk'))
		)

		build_relationship_site(collections: %w[pages], relationships: scoped_relationships, files: files) do |site, _files|
			reference = document_for(site, 'pages', 'source').data.fetch('relationships').fetch('pages').first

			expect(reference.fetch('scope')).to eq('locale' => 'fr', 'meta.region' => 'uk')
			expect(reference.fetch('page').basename_without_ext).to eq('target-fr')
		end
	end

	it 'treats dotted scope override keys as literal configured field names' do
		files = relationship_site_files(
			collection_document('pages', 'source', scoped_page(
				id: 'A',
				locale: 'en',
				region: 'uk',
				references: {
					'id' => 'B',
					'scope' => { 'meta.region' => 'eu' }
				}
			)),
			collection_document('pages', 'target-uk', scoped_page(id: 'B', locale: 'en', region: 'uk')),
			collection_document('pages', 'target-eu', scoped_page(id: 'B', locale: 'en', region: 'eu'))
		)

		build_relationship_site(collections: %w[pages], relationships: scoped_relationships, files: files) do |site, _files|
			reference = document_for(site, 'pages', 'source').data.fetch('relationships').fetch('pages').first

			expect(reference.fetch('scope')).to eq('locale' => 'en', 'meta.region' => 'eu')
			expect(reference.fetch('page').basename_without_ext).to eq('target-eu')
		end
	end

	it 'supports a custom reference property mapped to the singular scope placeholder' do
		relationships = scoped_relationships(
			'references' => {
				'id' => '<key>',
				'collection' => '<collection>',
				'context' => '<scope>',
				'page' => '<page>'
			}
		)
		files = relationship_site_files(
			collection_document('pages', 'source', scoped_page(
				id: 'A',
				locale: 'en',
				region: 'uk',
				references: {
					'id' => 'B',
					'context' => { 'locale' => 'fr' }
				}
			)),
			collection_document('pages', 'target-en', scoped_page(id: 'B', locale: 'en', region: 'uk')),
			collection_document('pages', 'target-fr', scoped_page(id: 'B', locale: 'fr', region: 'uk'))
		)

		build_relationship_site(collections: %w[pages], relationships: relationships, files: files) do |site, _files|
			reference = document_for(site, 'pages', 'source').data.fetch('relationships').fetch('pages').first

			expect(reference.fetch('context')).to eq('locale' => 'fr', 'meta.region' => 'uk')
			expect(reference.fetch('page').basename_without_ext).to eq('target-fr')
			expect(reference).not_to have_key('scope')
		end
	end

	it 'rejects duplicate primary keys within the same collection and exact scope' do
		files = relationship_site_files(
			collection_document('pages', 'first', scoped_page(id: 'B', locale: 'en', region: 'uk')),
			collection_document('pages', 'second', scoped_page(id: 'B', locale: 'en', region: 'uk'))
		)

		expect do
			build_relationship_site(collections: %w[pages], relationships: scoped_relationships, files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /pages -> pages.*primary key `B`.*scope.*first.*second/i)
	end

	it 'keeps scoped and explicitly unscoped targets independent in the same configuration' do
		relationships = {
			'frontmatter' => {
				'base' => '',
				'primary' => 'id',
				'scope' => 'locale',
				'foreign' => 'links.<collection>'
			},
			'relationships' => [
				{
					'from' => 'sources',
					'to' => [
						'pages',
						{
							'collection' => 'services',
							'frontmatter' => { 'scope' => nil }
						}
					]
				}
			]
		}
		files = relationship_site_files(
			collection_document('sources', 'source', {
				'id' => 'A',
				'locale' => 'en',
				'links' => {
					'pages' => 'B',
					'services' => 'S'
				}
			}),
			collection_document('pages', 'page-en', { 'id' => 'B', 'locale' => 'en' }),
			collection_document('pages', 'page-fr', { 'id' => 'B', 'locale' => 'fr' }),
			collection_document('services', 'service', { 'id' => 'S' })
		)

		build_relationship_site(collections: %w[sources pages services], relationships: relationships, files: files) do |site, _files|
			links = document_for(site, 'sources', 'source').data.fetch('links')
			page_reference = links.fetch('pages').first
			service_reference = links.fetch('services').first

			expect(page_reference.fetch('scope')).to eq('locale' => 'en')
			expect(page_reference.fetch('page').basename_without_ext).to eq('page-en')
			expect(service_reference.fetch('id')).to eq('S')
			expect(service_reference).not_to have_key('scope')
		end
	end

	it 'preserves an ordinary scope metadata property when no relationship configures scope' do
		relationships = {
			'relationships' => [
				{ 'from' => 'pages', 'to' => 'self' }
			]
		}
		files = relationship_site_files(
			collection_document('pages', 'source', {
				'relationships' => {
					'pages' => {
						'id' => 'pages/target',
						'scope' => 'ordinary metadata'
					}
				}
			}),
			collection_document('pages', 'target')
		)

		build_relationship_site(collections: %w[pages], relationships: relationships, files: files) do |site, _files|
			reference = document_for(site, 'pages', 'source').data.fetch('relationships').fetch('pages').first

			expect(reference.fetch('id')).to eq('pages/target')
			expect(reference.fetch('scope')).to eq('ordinary metadata')
		end
	end

	it 'matches scope values by exact Ruby value rather than string coercion' do
		files = relationship_site_files(
			collection_document('pages', 'source', scoped_page(id: 'A', locale: 'en', region: 1, references: 'B')),
			collection_document('pages', 'target-number', scoped_page(id: 'B', locale: 'en', region: 1)),
			collection_document('pages', 'target-string', scoped_page(id: 'B', locale: 'en', region: '1'))
		)

		build_relationship_site(collections: %w[pages], relationships: scoped_relationships, files: files) do |site, _files|
			reference = document_for(site, 'pages', 'source').data.fetch('relationships').fetch('pages').first

			expect(reference.fetch('scope')).to eq('locale' => 'en', 'meta.region' => 1)
			expect(reference.fetch('page').basename_without_ext).to eq('target-number')
		end
	end

	it 'does not fall back to a same-key target when a scope field differs' do
		files = relationship_site_files(
			collection_document('pages', 'source', scoped_page(id: 'A', locale: 'en', region: 'us', references: 'B')),
			collection_document('pages', 'target', scoped_page(id: 'B', locale: 'en', region: 'uk'))
		)

		expect do
			build_relationship_site(collections: %w[pages], relationships: scoped_relationships, files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /pages -> pages.*target.*scope field `meta.region`.*uk.*us.*source/i)
	end

	it 'preserves cross-collection ambiguity when key and complete scope both match' do
		relationships = {
			'frontmatter' => {
				'base' => '',
				'primary' => 'id',
				'scope' => 'locale',
				'foreign' => 'links'
			},
			'relationships' => [
				{ 'from' => 'sources', 'to' => 'pages, articles' }
			]
		}
		files = relationship_site_files(
			collection_document('sources', 'source', { 'id' => 'A', 'locale' => 'en', 'links' => 'B' }),
			collection_document('pages', 'page', { 'id' => 'B', 'locale' => 'en' }),
			collection_document('articles', 'article', { 'id' => 'B', 'locale' => 'en' })
		)

		expect do
			build_relationship_site(collections: %w[sources pages articles], relationships: relationships, files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /key-only reference `B` is ambiguous across collections: articles, pages/i)
	end

	it 'reports missing source and target scope fields with relationship and document details' do
		missing_source_files = relationship_site_files(
			collection_document('pages', 'source', {
				'meta' => { 'id' => 'A', 'region' => 'uk' },
				'relationships' => { 'pages' => 'B' }
			}),
			collection_document('pages', 'target', scoped_page(id: 'B', locale: 'en', region: 'uk'))
		)
		expect do
			build_relationship_site(collections: %w[pages], relationships: scoped_relationships, files: missing_source_files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /pages -> pages.*source.*scope field `locale`/i)

		missing_target_files = relationship_site_files(
			collection_document('pages', 'source', scoped_page(id: 'A', locale: 'en', region: 'uk', references: 'B')),
			collection_document('pages', 'target', {
				'meta' => { 'id' => 'B' },
				'locale' => 'en'
			})
		)
		expect do
			build_relationship_site(collections: %w[pages], relationships: scoped_relationships, files: missing_target_files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /pages -> pages.*target.*scope field `meta.region`/i)
	end

	it 'rejects null and unconfigured scope overrides with relationship, document, and field details' do
		[{'locale' => nil}, {'variant' => 'mobile'}].each do |scope_override|
			files = relationship_site_files(
				collection_document('pages', 'source', scoped_page(
					id: 'A',
					locale: 'en',
					region: 'uk',
					references: { 'id' => 'B', 'scope' => scope_override }
				)),
				collection_document('pages', 'target', scoped_page(id: 'B', locale: 'en', region: 'uk'))
			)

			expect do
				build_relationship_site(collections: %w[pages], relationships: scoped_relationships, files: files) { |_site, _files| nil }
			end.to raise_error(JekyllTestHarness::SiteBuildError, /pages -> pages.*source.*scope field `(locale|variant)`/i)
		end
	end

	it 'requires the reserved scope property to be a hash, including when it is explicitly null' do
		[nil, 'fr', []].each do |invalid_scope|
			files = relationship_site_files(
				collection_document('pages', 'source', scoped_page(
					id: 'A',
					locale: 'en',
					region: 'uk',
					references: { 'id' => 'B', 'scope' => invalid_scope }
				)),
				collection_document('pages', 'target', scoped_page(id: 'B', locale: 'en', region: 'uk'))
			)

			expect do
				build_relationship_site(collections: %w[pages], relationships: scoped_relationships, files: files) { |_site, _files| nil }
			end.to raise_error(JekyllTestHarness::SiteBuildError, /pages -> pages.*source.*scope property.*must be a hash/i)
		end
	end

	it 'keeps same-key targets in different scopes distinct while counting duplicates and writing to a separate output path' do
		relationships = scoped_relationships(
			'multiple' => 'count',
			'frontmatter' => {
				'output' => 'resolved.pages'
			}
		)
		raw_references = [
			{ 'id' => 'B', 'count' => 2, 'note' => 'first' },
			{ 'id' => 'B', 'note' => 'later' },
			{ 'id' => 'B', 'scope' => { 'locale' => 'fr' }, 'count' => 4 }
		]
		files = relationship_site_files(
			collection_document('pages', 'source', scoped_page(id: 'A', locale: 'en', region: 'uk', references: raw_references)),
			collection_document('pages', 'target-en', scoped_page(id: 'B', locale: 'en', region: 'uk')),
			collection_document('pages', 'target-fr', scoped_page(id: 'B', locale: 'fr', region: 'uk'))
		)

		build_relationship_site(collections: %w[pages], relationships: relationships, files: files) do |site, _files|
			source = document_for(site, 'pages', 'source')
			references = source.data.fetch('resolved').fetch('pages')

			expect(source.data.fetch('relationships').fetch('pages')).to eq(raw_references)
			expect(reference_ids(references)).to eq(['B', 'B'])
			expect(reference_values(references, 'scope')).to eq([
				{ 'locale' => 'en', 'meta.region' => 'uk' },
				{ 'locale' => 'fr', 'meta.region' => 'uk' }
			])
			expect(reference_values(references, 'count')).to eq([3, 4])
			expect(references.first.fetch('note')).to eq('first')
		end
	end

	it 'hydrates each direction of a cross-scope bidirectional link with the target document scope' do
		relationships = {
			'frontmatter' => {
				'base' => '',
				'primary' => 'id',
				'scope' => 'locale',
				'foreign' => 'links.<collection>'
			},
			'relationships' => [
				{ 'from' => 'products', 'to' => 'services', 'mode' => 'bidirectional' }
			]
		}
		files = relationship_site_files(
			collection_document('products', 'product-en', {
				'id' => 'A',
				'locale' => 'en',
				'links' => {
					'services' => {
						'id' => 'B',
						'scope' => { 'locale' => 'fr' }
					}
				}
			}),
			collection_document('services', 'service-en', { 'id' => 'B', 'locale' => 'en' }),
			collection_document('services', 'service-fr', { 'id' => 'B', 'locale' => 'fr' })
		)

		build_relationship_site(collections: %w[products services], relationships: relationships, files: files) do |site, _files|
			product_reference = document_for(site, 'products', 'product-en').data.fetch('links').fetch('services').first
			reverse_reference = document_for(site, 'services', 'service-fr').data.fetch('links').fetch('products').first

			expect(product_reference.fetch('scope')).to eq('locale' => 'fr')
			expect(product_reference.fetch('page').basename_without_ext).to eq('service-fr')
			expect(reverse_reference.fetch('scope')).to eq('locale' => 'en')
			expect(reverse_reference.fetch('page').basename_without_ext).to eq('product-en')
			expect(document_for(site, 'services', 'service-en').data.fetch('links').fetch('products')).to eq([])
		end
	end

	it 'lets resolvers inherit or override scope while preventing metadata from overwriting it' do
		define_resolver('ScopedServiceAdder', from: 'products', to: 'services') do
			def resolve
				link('B', reference: {
					'scope' => { 'locale' => 'wrong' },
					'note' => 'inherited'
				})
				link(
					{
						'id' => 'B',
						'scope' => { 'locale' => 'fr' }
					},
					reference: {
						'scope' => { 'locale' => 'wrong' },
						'note' => 'overridden'
					}
				)
			end
		end

		relationships = {
			'frontmatter' => {
				'base' => '',
				'primary' => 'id',
				'scope' => 'locale',
				'foreign' => 'links.<collection>'
			},
			'relationships' => [
				{ 'from' => 'products', 'to' => 'services' }
			]
		}
		files = relationship_site_files(
			collection_document('products', 'product', { 'id' => 'A', 'locale' => 'en' }),
			collection_document('services', 'service-en', { 'id' => 'B', 'locale' => 'en' }),
			collection_document('services', 'service-fr', { 'id' => 'B', 'locale' => 'fr' })
		)

		build_relationship_site(collections: %w[products services], relationships: relationships, files: files) do |site, _files|
			references = document_for(site, 'products', 'product').data.fetch('links').fetch('services')

			expect(reference_values(references, 'scope')).to eq([
				{ 'locale' => 'en' },
				{ 'locale' => 'fr' }
			])
			expect(reference_values(references, 'note')).to eq(%w[inherited overridden])
			expect(references.map { |reference| reference.fetch('page').basename_without_ext }).to eq(%w[service-en service-fr])
		end
	end

	it 'resolves tree references within scope and hydrates tree outputs with complete scope' do
		relationships = {
			'frontmatter' => {
				'base' => '',
				'primary' => 'id',
				'scope' => 'locale'
			},
			'relationships' => [
				{ 'from' => 'pages', 'to' => 'self', 'mode' => 'parent' }
			]
		}
		files = relationship_site_files(
			collection_document('pages', 'root-en', { 'id' => 'B', 'locale' => 'en' }),
			collection_document('pages', 'root-fr', { 'id' => 'B', 'locale' => 'fr' }),
			collection_document('pages', 'leaf-en', { 'id' => 'A', 'locale' => 'en', 'parent' => 'B' }),
			collection_document('pages', 'leaf-fr', { 'id' => 'A', 'locale' => 'fr', 'parent' => 'B' })
		)

		build_relationship_site(collections: %w[pages], relationships: relationships, files: files) do |site, _files|
			en_parent = document_for(site, 'pages', 'leaf-en').data.fetch('parents').first
			fr_parent = document_for(site, 'pages', 'leaf-fr').data.fetch('parents').first

			expect(en_parent.fetch('scope')).to eq('locale' => 'en')
			expect(en_parent.fetch('page').basename_without_ext).to eq('root-en')
			expect(fr_parent.fetch('scope')).to eq('locale' => 'fr')
			expect(fr_parent.fetch('page').basename_without_ext).to eq('root-fr')
		end
	end

	it 'keeps URL-inferred tree edges inside the child document scope' do
		relationships = {
			'frontmatter' => {
				'base' => '',
				'primary' => 'id',
				'scope' => 'locale'
			},
			'tree' => {
				'url' => true
			},
			'relationships' => [
				{ 'from' => 'pages', 'to' => 'self', 'mode' => 'parent' }
			]
		}
		files = relationship_site_files(
			collection_document('pages', 'root-en', { 'id' => 'B', 'locale' => 'en', 'permalink' => '/guides/index.html' }),
			collection_document('pages', 'root-fr', { 'id' => 'B', 'locale' => 'fr', 'permalink' => '/guides/index.html' }),
			collection_document('pages', 'leaf-en', { 'id' => 'A', 'locale' => 'en', 'permalink' => '/guides/intro/' }),
			collection_document('pages', 'leaf-fr', { 'id' => 'A', 'locale' => 'fr', 'permalink' => '/guides/intro/' })
		)

		build_relationship_site(collections: %w[pages], relationships: relationships, files: files) do |site, _files|
			en_parent = document_for(site, 'pages', 'leaf-en').data.fetch('parents').first
			fr_parent = document_for(site, 'pages', 'leaf-fr').data.fetch('parents').first

			expect(en_parent.fetch('page').basename_without_ext).to eq('root-en')
			expect(en_parent.fetch('scope')).to eq('locale' => 'en')
			expect(fr_parent.fetch('page').basename_without_ext).to eq('root-fr')
			expect(fr_parent.fetch('scope')).to eq('locale' => 'fr')
		end
	end

	it 'uses scoped links during pruning and preserves their scope after rebuilding the surviving graph' do
		relationships = {
			'frontmatter' => {
				'base' => '',
				'primary' => 'id',
				'scope' => 'locale',
				'foreign' => 'links.<collection>'
			},
			'relationships' => [
				{
					'from' => 'products',
					'to' => 'pages',
					'prune' => { 'min' => 1 }
				}
			]
		}
		files = relationship_site_files(
			collection_document('products', 'kept', {
				'id' => 'K',
				'locale' => 'en',
				'links' => { 'pages' => 'B' }
			}),
			collection_document('products', 'pruned', { 'id' => 'P', 'locale' => 'fr' }),
			collection_document('pages', 'page-en', { 'id' => 'B', 'locale' => 'en' }),
			collection_document('pages', 'page-fr', { 'id' => 'B', 'locale' => 'fr' })
		)

		build_relationship_site(collections: %w[products pages], relationships: relationships, files: files) do |site, _files|
			expect(site.collections.fetch('products').docs.map(&:basename_without_ext)).to eq(['kept'])

			reference = document_for(site, 'products', 'kept').data.fetch('links').fetch('pages').first
			expect(reference.fetch('scope')).to eq('locale' => 'en')
			expect(reference.fetch('page').basename_without_ext).to eq('page-en')
		end
	end

	it 'requires custom reference templates to define the scope placeholder' do
		expect do
			Jekyll::Plugins::Relationships::Configuration.new(
				'relationships' => scoped_relationships(
					'references' => {
						'id' => '<key>',
						'page' => '<page>'
					}
				)
			)
		end.to raise_error(Jekyll::Plugins::Relationships::ConfigurationError, /must define exactly one <scope> property/i)
	end

	it 'allows only one reference property to map to the scope placeholder' do
		expect do
			Jekyll::Plugins::Relationships::Configuration.new(
				'relationships' => scoped_relationships(
					'references' => {
						'id' => '<key>',
						'scope' => '<scope>',
						'context' => '<scope>',
						'page' => '<page>'
					}
				)
			)
		end.to raise_error(Jekyll::Plugins::Relationships::ConfigurationError, /only define one <scope> property/i)
	end

	it 'validates scope configuration types and path entries' do
		[false, {}, [], ['locale', '']].each do |invalid_scope|
			expect do
				Jekyll::Plugins::Relationships::Configuration.new(
					'relationships' => scoped_relationships(
						'frontmatter' => {
							'scope' => invalid_scope
						}
					)
				)
			end.to raise_error(Jekyll::Plugins::Relationships::ConfigurationError, /frontmatter.scope.*non-empty path strings/i)
		end
	end

	it 'applies scope overrides at relationship and target levels' do
		configuration = Jekyll::Plugins::Relationships::Configuration.new(
			'relationships' => {
				'frontmatter' => {
					'base' => '',
					'scope' => 'global_scope'
				},
				'relationships' => [
					{
						'from' => 'pages',
						'frontmatter' => {
							'scope' => 'relationship_scope'
						},
						'to' => [
							'articles',
							{
								'collection' => 'services',
								'frontmatter' => {
									'scope' => 'locale, meta.region'
								}
							}
						]
					}
				]
			}
		)

		expect(configuration.normal_relationship_for(from_collection: 'pages', to_collection: 'articles').scope_fields.map(&:name)).to eq(['relationship_scope'])
		expect(configuration.normal_relationship_for(from_collection: 'pages', to_collection: 'services').scope_fields.map(&:name)).to eq(['locale', 'meta.region'])
	end

	it 'applies the active frontmatter base to document scope paths without changing literal reference keys' do
		configuration = Jekyll::Plugins::Relationships::Configuration.new(
			'relationships' => {
				'frontmatter' => {
					'base' => 'data',
					'primary' => 'meta.id',
					'scope' => 'locale, meta.region'
				},
				'relationships' => [
					{ 'from' => 'pages', 'to' => 'self' }
				]
			}
		)
		scope_fields = configuration.normal_relationship_for(from_collection: 'pages', to_collection: 'pages').scope_fields

		expect(scope_fields.map(&:name)).to eq(['locale', 'meta.region'])
		expect(scope_fields.map(&:path)).to eq(['data.locale', 'data.meta.region'])
	end
end
