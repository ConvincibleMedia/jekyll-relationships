# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'normal relationships' do
	it 'resolves default one-way links and upgrades strings into hashes' do
		relationships = {
			'relationships' => [
				{ 'from' => 'products', 'to' => 'categories' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'shoes', {
				'relationships' => {
					'categories' => ['categories/trainers']
				}
			}),
			collection_document('categories', 'trainers')
		)

		build_relationship_site(collections: %w[products categories], relationships: relationships, files: files) do |site, _files|
			product = document_for(site, 'products', 'shoes')
			category = document_for(site, 'categories', 'trainers')
			references = product.data.fetch('relationships').fetch('categories')

			expect(references.length).to eq(1)
			expect(references.first.fetch('id')).to eq('categories/trainers')
			expect(references.first.fetch('collection')).to eq('categories')
			expect(references.first.fetch('page')).to eq(category)
			expect(references.first.fetch('count')).to eq(1)
			expect(category.data.fetch('relationships', {})).not_to have_key('products')
		end
	end

	it 'emits debug logs that trace raw inputs, resolver activity, and final write-back' do
		define_resolver('DebugTraceResolver', from: 'products', to: 'categories') do
			def resolve
				document('products/alpha')
				relationships
				link('categories/extra', reference: { 'source' => 'resolver' })
			end
		end

		relationships = {
			'debug' => true,
			'relationships' => [
				{ 'from' => 'products', 'to' => 'categories' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'alpha', {
				'relationships' => {
					'categories' => ['categories/one']
				}
			}),
			collection_document('categories', 'one'),
			collection_document('categories', 'extra')
		)

		debug_messages = []
		allow(Jekyll.logger).to receive(:info) do |topic, message|
			next unless topic == 'Relationships:'
			next unless message.include?('[debug]')

			debug_messages << message
		end

		build_relationship_site(collections: %w[products categories], relationships: relationships, files: files) do |_site, _files|
			nil
		end

		expect(debug_messages).to include(a_string_including('_products/alpha.md (products -> categories) resolve_start'))
		expect(debug_messages).to include(a_string_including('_products/alpha.md (products -> categories) raw_path'))
		expect(debug_messages).to include(a_string_including('value=["categories/one"]'))
		expect(debug_messages).to include(a_string_including('_products/alpha.md (products -> categories) resolver_start'))
		expect(debug_messages).to include(a_string_including('resolver="Jekyll::Plugins::Relationships::Resolvers::DebugTraceResolver"'))
		expect(debug_messages).to include(a_string_including('_products/alpha.md (products -> categories) resolver_relationships'))
		expect(debug_messages).to include(a_string_including('_products/alpha.md (products -> categories) link'))
		expect(debug_messages).to include(a_string_including('origin="resolver Jekyll::Plugins::Relationships::Resolvers::DebugTraceResolver"'))
		expect(debug_messages).to include(a_string_including('target_key="categories/extra"'))
		expect(debug_messages).to include(a_string_including('_products/alpha.md write_output'))
		expect(debug_messages).to include(a_string_including('path="relationships.categories"'))
	end

	it 'counts duplicate links gathered from multiple input paths and rewrites the final set onto the first path' do
		define_resolver('FirstPathDeduper', from: 'products', to: 'categories') do
			def resolve
				link('categories/extra', reference: { 'source' => 'resolver' })
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

		files = relationship_site_files(
			collection_document('products', 'alpha', {
				'data' => {
					'primary' => {
						'categories' => [
							'categories/one',
							{ 'id' => 'categories/two', 'note' => 'first-seen-here' },
							'categories/one'
						]
					},
					'secondary' => ['categories/two', 'categories/three']
				}
			}),
			collection_document('categories', 'one'),
			collection_document('categories', 'two'),
			collection_document('categories', 'three'),
			collection_document('categories', 'extra')
		)

		build_relationship_site(collections: %w[products categories], relationships: relationships, files: files) do |site, _files|
			product = document_for(site, 'products', 'alpha')
			data = product.data.fetch('data')
			primary_links = data.fetch('primary').fetch('categories')
			secondary_links = data.fetch('secondary')

			expect(reference_ids(primary_links)).to eq([
				'categories/one',
				'categories/two',
				'categories/three',
				'categories/extra'
			])
			expect(reference_values(primary_links, 'count')).to eq([2, 2, 1, 1])
			expect(primary_links[1].fetch('note')).to eq('first-seen-here')
			expect(primary_links.last.fetch('source')).to eq('resolver')
			expect(reference_ids(secondary_links)).to eq(['categories/two', 'categories/three'])
			expect(reference_values(secondary_links, 'count')).to eq([1, 1])
		end
	end

	it 'writes the final link set to a separate output path when configured' do
		define_resolver('SeparateOutputAdder', from: 'products', to: 'categories') do
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

		files = relationship_site_files(
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

		build_relationship_site(collections: %w[products categories], relationships: relationships, files: files) do |site, _files|
			product = document_for(site, 'products', 'alpha')
			data = product.data.fetch('data')

			expect(reference_ids(data.fetch('primary').fetch('categories'))).to eq(['categories/one'])
			expect(reference_ids(data.fetch('secondary'))).to eq(['categories/two'])
			expect(reference_ids(data.fetch('resolved').fetch('categories'))).to eq([
				'categories/one',
				'categories/two',
				'categories/extra'
			])
			expect(reference_values(data.fetch('resolved').fetch('categories'), 'count')).to eq([1, 1, 1])
		end
	end

	it 'resolves collection placeholders in separate output paths' do
		relationships = {
			'frontmatter' => {
				'base' => 'data',
				'foreign' => 'refs.<collection>',
				'output' => 'resolved.<collection>'
			},
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'services, articles' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'data' => {
					'refs' => {
						'services' => ['services/design'],
						'articles' => ['articles/launch-notes']
					}
				}
			}),
			collection_document('services', 'design'),
			collection_document('articles', 'launch-notes')
		)

		build_relationship_site(collections: %w[projects services articles], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			resolved = project.data.fetch('data').fetch('resolved')

			expect(reference_ids(resolved.fetch('services'))).to eq(['services/design'])
			expect(reference_ids(resolved.fetch('articles'))).to eq(['articles/launch-notes'])
		end
	end

	it 'mirrors bidirectional links onto the reverse relationship when read from frontmatter' do
		relationships = {
			'relationships' => [
				{ 'from' => 'products', 'to' => 'services', 'mode' => 'bidirectional' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'alpha', {
				'relationships' => {
					'services' => ['services/design']
				}
			}),
			collection_document('services', 'design')
		)

		build_relationship_site(collections: %w[products services], relationships: relationships, files: files) do |site, _files|
			service = document_for(site, 'services', 'design')
			expect(reference_ids(service.data.fetch('relationships').fetch('products'))).to eq(['products/alpha'])
		end
	end

	it 'mirrors resolver additions and removals across bidirectional relationships' do
		define_resolver('BidirectionalSwap', from: 'products', to: 'services') do
			def resolve
				unlink('services/design')
				link('services/strategy')
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'products', 'to' => 'services', 'mode' => 'bidirectional' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'alpha', {
				'relationships' => {
					'services' => ['services/design']
				}
			}),
			collection_document('services', 'design'),
			collection_document('services', 'strategy')
		)

		build_relationship_site(collections: %w[products services], relationships: relationships, files: files) do |site, _files|
			product = document_for(site, 'products', 'alpha')
			design = document_for(site, 'services', 'design')
			strategy = document_for(site, 'services', 'strategy')

			expect(reference_ids(product.data.fetch('relationships').fetch('services'))).to eq(['services/strategy'])
			expect(design.data.fetch('relationships').fetch('products')).to eq([])
			expect(reference_ids(strategy.data.fetch('relationships').fetch('products'))).to eq(['products/alpha'])
		end
	end

	it 'merges multiple relationship states onto one shared output path in sequence order' do
		relationships = {
			'frontmatter' => {
				'base' => 'data',
				'foreign' => 'refs.<collection>'
			},
			'relationships' => [
				{
					'from' => 'projects',
					'to' => 'services',
					'frontmatter' => {
						'output' => 'resolved.related'
					}
				},
				{
					'from' => 'projects',
					'to' => 'articles',
					'frontmatter' => {
						'output' => 'resolved.related'
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'data' => {
					'refs' => {
						'services' => ['services/design'],
						'articles' => ['articles/launch-notes']
					}
				}
			}),
			collection_document('services', 'design'),
			collection_document('articles', 'launch-notes')
		)

		build_relationship_site(collections: %w[projects services articles], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			related = project.data.fetch('data').fetch('resolved').fetch('related')

			expect(reference_ids(related)).to eq(['services/design', 'articles/launch-notes'])
			expect(reference_values(related, 'count')).to eq([1, 1])
		end
	end

	it 'supports explicit counts and merges duplicate metadata under the first occurrence' do
		relationships = {
			'relationships' => [
				{ 'from' => 'products', 'to' => 'categories' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'alpha', {
				'relationships' => {
					'categories' => [
						{
							'id' => 'categories/one',
							'count' => 2,
							'details' => {
								'keep' => 'first',
								'source' => 'raw'
							}
						},
						{
							'id' => 'categories/one',
							'details' => {
								'keep' => 'later',
								'added' => 'second'
							},
							'note' => 'later-note'
						},
						{
							'id' => 'categories/two',
							'count' => 3
						}
					]
				}
			}),
			collection_document('categories', 'one'),
			collection_document('categories', 'two')
		)

		build_relationship_site(collections: %w[products categories], relationships: relationships, files: files) do |site, _files|
			product = document_for(site, 'products', 'alpha')
			references = product.data.fetch('relationships').fetch('categories')
			first_reference = references.first

			expect(reference_ids(references)).to eq(['categories/one', 'categories/two'])
			expect(reference_values(references, 'count')).to eq([3, 3])
			expect(first_reference.fetch('details')).to eq({
				'keep' => 'first',
				'source' => 'raw',
				'added' => 'second'
			})
			expect(first_reference.fetch('note')).to eq('later-note')
		end
	end

	it 'supports legacy duplicate dropping without writing count fields' do
		relationships = {
			'multiple' => 'drop',
			'relationships' => [
				{ 'from' => 'products', 'to' => 'categories' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'alpha', {
				'relationships' => {
					'categories' => ['categories/one', 'categories/one', 'categories/two']
				}
			}),
			collection_document('categories', 'one'),
			collection_document('categories', 'two')
		)

		build_relationship_site(collections: %w[products categories], relationships: relationships, files: files) do |site, _files|
			product = document_for(site, 'products', 'alpha')
			references = product.data.fetch('relationships').fetch('categories')

			expect(reference_ids(references)).to eq(['categories/one', 'categories/two'])
			expect(references).to all(satisfy { |reference| !reference.key?('count') })
		end
	end

	it 'supports keeping duplicate links without deduping them' do
		relationships = {
			'multiple' => 'keep',
			'relationships' => [
				{ 'from' => 'products', 'to' => 'categories' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'alpha', {
				'relationships' => {
					'categories' => ['categories/one', 'categories/one', 'categories/two']
				}
			}),
			collection_document('categories', 'one'),
			collection_document('categories', 'two')
		)

		build_relationship_site(collections: %w[products categories], relationships: relationships, files: files) do |site, _files|
			product = document_for(site, 'products', 'alpha')
			references = product.data.fetch('relationships').fetch('categories')

			expect(reference_ids(references)).to eq(['categories/one', 'categories/one', 'categories/two'])
			expect(references).to all(satisfy { |reference| !reference.key?('count') })
		end
	end

	it 'sorts counted links by descending count while retaining first-seen order for ties' do
		relationships = {
			'multiple' => {
				'mode' => 'count',
				'sort' => 'desc'
			},
			'relationships' => [
				{ 'from' => 'products', 'to' => 'categories' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'alpha', {
				'relationships' => {
					'categories' => [
						'categories/three',
						'categories/one',
						'categories/two',
						'categories/three',
						'categories/one'
					]
				}
			}),
			collection_document('categories', 'one'),
			collection_document('categories', 'two'),
			collection_document('categories', 'three')
		)

		build_relationship_site(collections: %w[products categories], relationships: relationships, files: files) do |site, _files|
			product = document_for(site, 'products', 'alpha')
			references = product.data.fetch('relationships').fetch('categories')

			expect(reference_ids(references)).to eq(['categories/three', 'categories/one', 'categories/two'])
			expect(reference_values(references, 'count')).to eq([2, 2, 1])
		end
	end

	it 'sorts counted links after merging states onto one shared output path' do
		relationships = {
			'multiple' => {
				'mode' => 'count',
				'sort' => 'asc'
			},
			'frontmatter' => {
				'base' => 'data',
				'foreign' => 'refs.<collection>'
			},
			'relationships' => [
				{
					'from' => 'projects',
					'to' => 'services',
					'frontmatter' => {
						'output' => 'resolved.related'
					}
				},
				{
					'from' => 'projects',
					'to' => 'articles',
					'frontmatter' => {
						'output' => 'resolved.related'
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'data' => {
					'refs' => {
						'services' => ['services/design', 'services/design'],
						'articles' => ['articles/launch-notes']
					}
				}
			}),
			collection_document('services', 'design'),
			collection_document('articles', 'launch-notes')
		)

		build_relationship_site(collections: %w[projects services articles], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			related = project.data.fetch('data').fetch('resolved').fetch('related')

			expect(reference_ids(related)).to eq(['articles/launch-notes', 'services/design'])
			expect(reference_values(related, 'count')).to eq([1, 2])
		end
	end

	it 'preserves raw metadata and strips reserved properties from resolver metadata' do
		define_resolver('MetadataAugmenter', from: 'products', to: 'services') do
			def resolve
				link('services/strategy', reference: {
					'id' => 'ignored',
					'collection' => 'ignored',
					'page' => 'ignored',
					'count' => 99,
					'note' => 'resolver-note'
				})
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'products', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'alpha', {
				'relationships' => {
					'services' => [
						{ 'id' => 'services/design', 'note' => 'raw-note' }
					]
				}
			}),
			collection_document('services', 'design'),
			collection_document('services', 'strategy')
		)

		build_relationship_site(collections: %w[products services], relationships: relationships, files: files) do |site, _files|
			product = document_for(site, 'products', 'alpha')
			references = product.data.fetch('relationships').fetch('services')

			expect(references[0].fetch('note')).to eq('raw-note')
			expect(references[1].fetch('note')).to eq('resolver-note')
			expect(references[1].fetch('id')).to eq('services/strategy')
			expect(references[1].fetch('collection')).to eq('services')
			expect(references[1].fetch('page')).to be_a(Jekyll::Document)
			expect(references.map { |reference| reference.fetch('count') }).to eq([1, 1])
		end
	end
end
