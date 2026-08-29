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
			collection_document('pages', 'source', scoped_page(id: 'A', locale: 'en', region: 'uk', references: 'B')),
			collection_document('pages', 'target', scoped_page(id: 'B', locale: 'en', region: 'uk'))
		)

		build_relationship_site(collections: %w[pages], relationships: relationships, files: files) do |site, _files|
			reference = document_for(site, 'pages', 'source').data.fetch('relationships').fetch('pages').first

			expect(reference.fetch('context')).to eq('locale' => 'en', 'meta.region' => 'uk')
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

	it 'requires the reserved scope property to be a hash' do
		files = relationship_site_files(
			collection_document('pages', 'source', scoped_page(
				id: 'A',
				locale: 'en',
				region: 'uk',
				references: { 'id' => 'B', 'scope' => 'fr' }
			)),
			collection_document('pages', 'target', scoped_page(id: 'B', locale: 'en', region: 'uk'))
		)

		expect do
			build_relationship_site(collections: %w[pages], relationships: scoped_relationships, files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /scope property.*must be a hash/i)
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
end
