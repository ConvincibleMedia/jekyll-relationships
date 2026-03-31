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
			expect(references.first).not_to have_key('count')
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
			next unless message.include?('[debug:')

			debug_messages << message
		end

		build_relationship_site(collections: %w[products categories], relationships: relationships, files: files) do |_site, _files|
			nil
		end

		expect(debug_messages).to include(a_string_including('[debug:resolution] _products/alpha.md (products -> categories) resolve_start'))
		expect(debug_messages).to include(a_string_including('[debug:upgrading] _products/alpha.md (products -> categories) raw_path'))
		expect(debug_messages).to include(a_string_including('value=["categories/one"]'))
		expect(debug_messages).to include(a_string_including('[debug:resolvers] _products/alpha.md (products -> categories) resolver_start'))
		expect(debug_messages).to include(a_string_including('resolver="Jekyll::Plugins::Relationships::Resolvers::DebugTraceResolver"'))
		expect(debug_messages).to include(a_string_including('[debug:resolvers] _products/alpha.md (products -> categories) resolver_relationships'))
		expect(debug_messages).to include(a_string_including('[debug:mutations] _products/alpha.md (products -> categories) link'))
		expect(debug_messages).to include(a_string_including('origin="resolver Jekyll::Plugins::Relationships::Resolvers::DebugTraceResolver"'))
		expect(debug_messages).to include(a_string_including('target_key="categories/extra"'))
		expect(debug_messages).to include(a_string_including('[debug:upgrading] _products/alpha.md write_output'))
		expect(debug_messages).to include(a_string_including('path="relationships.categories"'))
	end

	it 'filters debug logs down to the requested areas when debug is configured as a string list' do
		define_resolver('UpgradingOnlyDebugTraceResolver', from: 'products', to: 'categories') do
			def resolve
				relationships
				link('categories/extra')
			end
		end

		relationships = {
			'debug' => 'upgrading',
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
			next unless message.include?('[debug:')

			debug_messages << message
		end

		build_relationship_site(collections: %w[products categories], relationships: relationships, files: files) do |_site, _files|
			nil
		end

		expect(debug_messages).to include(a_string_including('[debug:upgrading]'))
		expect(debug_messages).not_to include(a_string_including('[debug:resolution]'))
		expect(debug_messages).not_to include(a_string_including('[debug:mutations]'))
		expect(debug_messages).not_to include(a_string_including('[debug:resolvers]'))
		expect(debug_messages).to include(a_string_including('write_output'))
	end

	it 'filters debug logs down to events that relate to the configured IDs' do
		define_resolver('IdFilteredDebugTraceResolver', from: 'products', to: 'categories') do
			def resolve
				link('categories/extra')
			end
		end

		relationships = {
			'debug' => {
				'ids' => 'categories/extra',
				'log' => 'mutations'
			},
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
			next unless message.include?('[debug:')

			debug_messages << message
		end

		build_relationship_site(collections: %w[products categories], relationships: relationships, files: files) do |_site, _files|
			nil
		end

		expect(debug_messages).to include(a_string_including('[debug:mutations] _products/alpha.md (products -> categories) link'))
		expect(debug_messages).to include(a_string_including('target_key="categories/extra"'))
		expect(debug_messages).not_to include(a_string_including('target_key="categories/one"'))
		expect(debug_messages).not_to include(a_string_including('[debug:resolution]'))
	end

	it 'counts duplicate links gathered from multiple input paths and rewrites the final set onto the first path only' do
		define_resolver('FirstPathDeduper', from: 'products', to: 'categories') do
			def resolve
				link('categories/extra', reference: { 'source' => 'resolver' })
			end
		end

		relationships = {
			'multiple' => 'count',
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
			expect(secondary_links).to eq(['categories/two', 'categories/three'])
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

			expect(data.fetch('primary').fetch('categories')).to eq(['categories/one'])
			expect(data.fetch('secondary')).to eq(['categories/two'])
			expect(reference_ids(data.fetch('resolved').fetch('categories'))).to eq([
				'categories/one',
				'categories/two',
				'categories/extra'
			])
			expect(data.fetch('resolved').fetch('categories')).to all(satisfy { |reference| !reference.key?('count') })
		end
	end

	it 'leaves array-expanded raw references untouched while writing consolidated output elsewhere' do
		define_resolver('ArrayExpandedProjectAdder', from: 'projects', to: 'projects') do
			def resolve
				link('project-gamma', reference: { 'source' => 'resolver' })
			end
		end

		relationships = {
			'frontmatter' => {
				'base' => 'data',
				'primary' => 'id'
			},
			'relationships' => [
				{
					'from' => 'projects',
					'to' => [
						{
							'collection' => 'projects',
							'frontmatter' => {
								'foreign' => 'body.imagery.project',
								'output' => 'resolved.projects'
							}
						}
					]
				}
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'data' => {
					'id' => 'project-alpha',
					'body' => [
						{
							'block_type' => 'imagery',
							'imagery' => {
								'project' => {
									'id' => 'project-beta',
									'caption' => 'hero'
								}
							}
						},
						{
							'block_type' => 'imagery',
							'layout' => {
								'variant' => 'wide'
							},
							'imagery' => {
								'project' => {
									'id' => 'project-delta',
									'caption' => 'support'
								}
							}
						},
						{
							'block_type' => 'text',
							'content' => 'Keep me intact'
						}
					]
				}
			}),
			collection_document('projects', 'beta', {
				'data' => { 'id' => 'project-beta' }
			}),
			collection_document('projects', 'delta', {
				'data' => { 'id' => 'project-delta' }
			}),
			collection_document('projects', 'gamma', {
				'data' => { 'id' => 'project-gamma' }
			})
		)

		build_relationship_site(collections: %w[projects], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			body = project.data.fetch('data').fetch('body')
			first_project = body[0].fetch('imagery').fetch('project')
			second_project = body[1].fetch('imagery').fetch('project')
			resolved_projects = project.data.fetch('data').fetch('resolved').fetch('projects')

			expect(first_project).to eq({
				'id' => 'project-beta',
				'caption' => 'hero'
			})
			expect(second_project).to eq({
				'id' => 'project-delta',
				'caption' => 'support'
			})
			expect(body[1].fetch('layout')).to eq({ 'variant' => 'wide' })
			expect(body[2]).to eq({
				'block_type' => 'text',
				'content' => 'Keep me intact'
			})
			expect(reference_ids(resolved_projects)).to eq([
				'project-beta',
				'project-delta',
				'project-gamma'
			])
			expect(resolved_projects.last.fetch('source')).to eq('resolver')
		end
	end

	it 'requires a separate output path when the default consolidated write target spans an array' do
		relationships = {
			'frontmatter' => {
				'base' => 'data',
				'primary' => 'id',
				'foreign' => 'body.imagery.project'
			},
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'projects' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'data' => {
					'id' => 'project-alpha',
					'body' => [
						{
							'imagery' => {
								'project' => 'project-beta'
							}
						}
					]
				}
			}),
			collection_document('projects', 'beta', {
				'data' => { 'id' => 'project-beta' }
			})
		)

		expect do
			build_relationship_site(collections: %w[projects], relationships: relationships, files: files) { |_site, _files| nil }
		end.to raise_error(
			JekyllTestHarness::SiteBuildError,
			/spans across an array.*frontmatter\.output/i
		)
	end

	it 'allows array-expanded input paths when only the first input path receives the consolidated output' do
		define_resolver('PrimaryPathProjectAdder', from: 'projects', to: 'projects') do
			def resolve
				link('project-gamma')
			end
		end

		relationships = {
			'frontmatter' => {
				'base' => 'data',
				'primary' => 'id',
				'foreign' => ['primary_projects', 'body.imagery.project']
			},
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'projects' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'data' => {
					'id' => 'project-alpha',
					'primary_projects' => ['project-beta'],
					'body' => [
						{
							'imagery' => {
								'project' => {
									'id' => 'project-delta',
									'caption' => 'body block'
								}
							}
						}
					]
				}
			}),
			collection_document('projects', 'beta', {
				'data' => { 'id' => 'project-beta' }
			}),
			collection_document('projects', 'delta', {
				'data' => { 'id' => 'project-delta' }
			}),
			collection_document('projects', 'gamma', {
				'data' => { 'id' => 'project-gamma' }
			})
		)

		build_relationship_site(collections: %w[projects], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			data = project.data.fetch('data')
			body_project = data.fetch('body').first.fetch('imagery').fetch('project')

			expect(reference_ids(data.fetch('primary_projects'))).to eq([
				'project-beta',
				'project-delta',
				'project-gamma'
			])
			expect(body_project).to eq({
				'id' => 'project-delta',
				'caption' => 'body block'
			})
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

	it 'keeps quote frontmatter links ahead of service resolver additions in bidirectional mode' do
		define_resolver('ProjectServicesQuoteOrderProbe', from: 'projects', to: 'services') do
			def resolve
				# Force services -> quotes to resolve while the build is still walking
				# the project graph, before the quotes collection is resolved in the
				# normal top-level pass.
				relationships.each do |service|
					relationships(service, to: 'quotes')
				end
			end
		end

		define_resolver('QuoteServices', from: 'services', to: 'quotes') do
			def resolve
				relationships(to: 'projects').each do |project|
					relationships(project, to: 'clients').each do |client|
						relationships(client, to: 'quotes').each do |quote|
							link(quote)
						end
					end
				end
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'services', 'mode' => 'bidirectional' },
				{ 'from' => 'projects', 'to' => 'clients' },
				{ 'from' => 'clients', 'to' => 'quotes' },
				{
					'from' => 'quotes',
					'to' => 'services',
					'mode' => 'bidirectional',
					'frontmatter' => {
						'base' => '',
						'foreign' => 'data.related_services',
						'output' => 'relationships.<collection>'
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'relationships' => {
					'services' => ['services/design'],
					'clients' => ['clients/acme']
				}
			}),
			collection_document('clients', 'acme', {
				'relationships' => {
					'quotes' => ['quotes/derived']
				}
			}),
			collection_document('quotes', 'direct', {
				'data' => {
					'related_services' => ['services/design']
				}
			}),
			collection_document('quotes', 'derived'),
			collection_document('services', 'design')
		)

		build_relationship_site(collections: %w[projects clients quotes services], relationships: relationships, files: files) do |site, _files|
			service = document_for(site, 'services', 'design')
			references = service.data.fetch('relationships').fetch('quotes')

			expect(reference_ids(references)).to eq(['quotes/direct', 'quotes/derived'])
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
			expect(related).to all(satisfy { |reference| !reference.key?('count') })
		end
	end

	it 'supports explicit counts and merges duplicate metadata under the first occurrence' do
		relationships = {
			'multiple' => 'count',
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
			expect(references).to all(satisfy { |reference| !reference.key?('count') })
		end
	end
end
