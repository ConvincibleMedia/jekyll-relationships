# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'pruning' do
	it 'prunes normal relationship subjects when they have too few direct links' do
		relationships = {
			'relationships' => [
				{
					'from' => 'projects',
					'to' => 'categories',
					'prune' => {
						'min' => 1
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'kept', {
				'relationships' => {
					'categories' => ['categories/one']
				}
			}),
			collection_document('projects', 'pruned'),
			collection_document('categories', 'one')
		)

		build_relationship_site(collections: %w[projects categories], relationships: relationships, files: files) do |site, _files|
			expect(site.collections.fetch('projects').docs.map(&:basename_without_ext)).to eq(['kept'])
			expect(reference_ids(document_for(site, 'projects', 'kept').data.fetch('relationships').fetch('categories'))).to eq(['categories/one'])
		end
	end

	it 'supports integer prune shorthand for normal relationships' do
		relationships = {
			'relationships' => [
				{
					'from' => 'projects',
					'to' => 'categories',
					'prune' => 1
				}
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'kept', {
				'relationships' => {
					'categories' => ['categories/one']
				}
			}),
			collection_document('projects', 'pruned'),
			collection_document('categories', 'one')
		)

		build_relationship_site(collections: %w[projects categories], relationships: relationships, files: files) do |site, _files|
			expect(site.collections.fetch('projects').docs.map(&:basename_without_ext)).to eq(['kept'])
			expect(reference_ids(document_for(site, 'projects', 'kept').data.fetch('relationships').fetch('categories'))).to eq(['categories/one'])
		end
	end

	it 'prunes inverse normal relationship subjects after bidirectional resolution' do
		relationships = {
			'relationships' => [
				{
					'from' => 'projects',
					'to' => 'tags',
					'mode' => 'bidirectional',
					'prune' => {
						'mode' => 'inverse',
						'min' => 1
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'relationships' => {
					'tags' => ['tags/used']
				}
			}),
			collection_document('tags', 'used'),
			collection_document('tags', 'orphan')
		)

		build_relationship_site(collections: %w[projects tags], relationships: relationships, files: files) do |site, _files|
			expect(site.collections.fetch('tags').docs.map(&:basename_without_ext)).to eq(['used'])
			expect(reference_ids(document_for(site, 'tags', 'used').data.fetch('relationships').fetch('projects'))).to eq(['projects/alpha'])
		end
	end

	it 'combines counts across expanded direct prune relationships by default' do
		relationships = {
			'relationships' => [
				{
					'from' => 'products',
					'to' => 'categories, services',
					'prune' => {
						'min' => 2
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('products', 'kept', {
				'relationships' => {
					'categories' => ['categories/one'],
					'services' => ['services/design']
				}
			}),
			collection_document('products', 'only-category', {
				'relationships' => {
					'categories' => ['categories/one']
				}
			}),
			collection_document('products', 'only-service', {
				'relationships' => {
					'services' => ['services/design']
				}
			}),
			collection_document('categories', 'one'),
			collection_document('services', 'design')
		)

		build_relationship_site(collections: %w[products categories services], relationships: relationships, files: files) do |site, _files|
			expect(site.collections.fetch('products').docs.map(&:basename_without_ext)).to eq(['kept'])
		end
	end

	it 'treats expanded direct prune relationships as separate minimums when combine is false' do
		relationships = {
			'prune' => {
				'combine' => false
			},
			'relationships' => [
				{
					'from' => 'products',
					'to' => 'categories, services',
					'prune' => {
						'min' => 1
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('products', 'kept', {
				'relationships' => {
					'categories' => ['categories/one'],
					'services' => ['services/design']
				}
			}),
			collection_document('products', 'only-category', {
				'relationships' => {
					'categories' => ['categories/one']
				}
			}),
			collection_document('products', 'only-service', {
				'relationships' => {
					'services' => ['services/design']
				}
			}),
			collection_document('categories', 'one'),
			collection_document('services', 'design')
		)

		build_relationship_site(collections: %w[products categories services], relationships: relationships, files: files) do |site, _files|
			expect(site.collections.fetch('products').docs.map(&:basename_without_ext)).to eq(['kept'])
		end
	end

	it 'supports target-level pruning on hash-form targets with comma-delimited collections' do
		relationships = {
			'relationships' => [
				{
					'from' => 'projects',
					'to' => [
						{
							'collection' => 'projects',
							'frontmatter' => {
								'base' => '',
								'foreign' => 'data.body.imagery.projects'
							}
						},
						{
							'collection' => 'audiences, org_types, industries',
							'prune' => {
								'min' => 1
							}
						},
						{
							'collection' => 'clients',
							'frontmatter' => {
								'base' => '',
								'foreign' => 'data.client'
							},
							'mode' => 'bidirectional',
							'prune' => {
								'mode' => 'inverse',
								'min' => 1
							}
						}
					]
				}
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'relationships' => {
					'audiences' => ['audiences/one']
				},
				'data' => {
					'client' => 'clients/kept',
					'body' => {
						'imagery' => {
							'projects' => ['projects/alpha']
						}
					}
				}
			}),
			collection_document('projects', 'beta', {
				'data' => {
					'client' => 'clients/pruned'
				}
			}),
			collection_document('clients', 'kept'),
			collection_document('clients', 'pruned'),
			collection_document('audiences', 'one')
		)

		build_relationship_site(collections: %w[projects clients audiences org_types industries], relationships: relationships, files: files) do |site, _files|
			expect(site.collections.fetch('projects').docs.map(&:basename_without_ext)).to eq(['alpha'])
			expect(site.collections.fetch('clients').docs.map(&:basename_without_ext)).to eq(['kept'])
			expect(reference_ids(document_for(site, 'projects', 'alpha').data.fetch('relationships').fetch('audiences'))).to eq(['audiences/one'])
			expect(reference_ids(document_for(site, 'projects', 'alpha').data.fetch('data').fetch('body').fetch('imagery').fetch('projects'))).to eq(['projects/alpha'])
		end
	end

	it 'lets target-level prune false disable inherited pruning for that target only' do
		relationships = {
			'relationships' => [
				{
					'from' => 'projects',
					'to' => [
						'industries',
						{
							'collection' => 'clients',
							'prune' => false
						}
					],
					'prune' => {
						'min' => 1
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'client-only', {
				'relationships' => {
					'clients' => ['clients/acme']
				}
			}),
			collection_document('projects', 'industry-linked', {
				'relationships' => {
					'industries' => ['industries/finance']
				}
			}),
			collection_document('clients', 'acme'),
			collection_document('industries', 'finance')
		)

		build_relationship_site(collections: %w[projects clients industries], relationships: relationships, files: files) do |site, _files|
			expect(site.collections.fetch('projects').docs.map(&:basename_without_ext)).to eq(['industry-linked'])
			expect(site.collections.fetch('clients').docs.map(&:basename_without_ext)).to eq(['acme'])
			expect(reference_ids(document_for(site, 'projects', 'industry-linked').data.fetch('relationships').fetch('industries'))).to eq(['industries/finance'])
		end
	end

	it 'preserves explicitly persisted links while rerunning normal resolvers after pruning changes the active tree' do
		define_resolver('AncestorServiceLinker', from: 'pages', to: 'services') do
			def resolve
				ancestors.each do |ancestor|
					relationships(ancestor, to: 'services').each do |service|
						link(service, persist: true)
					end
				end
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'pages', 'to' => 'self', 'mode' => 'parent' },
				{ 'from' => 'pages', 'to' => 'services' },
				{
					'from' => 'pages',
					'to' => 'badges',
					'prune' => {
						'min' => 1
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('pages', 'root', {
				'relationships' => {
					'services' => ['services/root']
				}
			}),
			collection_document('pages', 'branch', {
				'relationships' => {
					'parent' => 'pages/root',
					'services' => ['services/branch'],
					'badges' => ['badges/branch']
				}
			}),
			collection_document('pages', 'leaf', {
				'relationships' => {
					'parent' => 'pages/branch',
					'badges' => ['badges/leaf']
				}
			}),
			collection_document('services', 'root'),
			collection_document('services', 'branch'),
			collection_document('badges', 'branch'),
			collection_document('badges', 'leaf')
		)

		build_relationship_site(collections: %w[pages services badges], relationships: relationships, files: files) do |site, _files|
			expect(site.collections.fetch('pages').docs.map(&:basename_without_ext)).to eq(%w[branch leaf])
			expect(document_for(site, 'pages', 'branch').data.fetch('relationships').fetch('parents')).to eq([])
			expect(reference_ids(document_for(site, 'pages', 'leaf').data.fetch('relationships').fetch('services'))).to eq(['services/branch', 'services/root'])
		end
	end

	it 'keeps direct bidirectional links ahead of resolver additions during prune reruns in count mode' do
		define_resolver('ProjectServicesQuoteOrderProbe', from: 'projects', to: 'services') do
			def resolve
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
			'multiple' => {
				'mode' => 'count'
			},
			'relationships' => [
				{
					'from' => 'projects',
					'to' => 'services',
					'mode' => 'bidirectional',
					'prune' => {
						'min' => 1
					}
				},
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
					'services' => ['services/branding'],
					'clients' => ['clients/acme']
				}
			}),
			collection_document('clients', 'acme', {
				'relationships' => {
					'quotes' => ['quotes/derived-one', 'quotes/derived-two', 'quotes/derived-three']
				}
			}),
			collection_document('quotes', 'direct', {
				'data' => {
					'related_services' => ['services/branding']
				}
			}),
			collection_document('quotes', 'derived-one'),
			collection_document('quotes', 'derived-two'),
			collection_document('quotes', 'derived-three'),
			collection_document('services', 'branding')
		)

		build_relationship_site(collections: %w[projects clients quotes services], relationships: relationships, files: files) do |site, _files|
			service = document_for(site, 'services', 'branding')
			references = service.data.fetch('relationships').fetch('quotes')

			expect(reference_ids(references)).to eq(['quotes/direct', 'quotes/derived-one', 'quotes/derived-two', 'quotes/derived-three'])
			expect(reference_values(references, 'count')).to eq([1, 1, 1, 1])
		end
	end

	it 'preserves explicitly persisted resolver-added links after inverse normal pruning removes their raw source links' do
		define_resolver('ClientIndustryAncestors', from: 'clients', to: 'industries') do
			def resolve
				relationships.each do |industry|
					ancestors(industry).each do |ancestor|
						link(ancestor, reference: { 'distance' => ancestor.fetch('distance') }, persist: true)
					end
				end
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'clients', 'to' => 'industries' },
				{ 'from' => 'industries', 'to' => 'self', 'mode' => 'parent' },
				{
					'from' => 'projects',
					'to' => 'industries',
					'prune' => {
						'mode' => 'inverse',
						'min' => 1
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('clients', 'beckett-rankine', {
				'relationships' => {
					'industries' => ['industries/architecture']
				}
			}),
			collection_document('industries', 'professional-services'),
			collection_document('industries', 'architecture', {
				'relationships' => {
					'parent' => 'industries/professional-services'
				}
			}),
			collection_document('projects', 'proof', {
				'relationships' => {
					'industries' => ['industries/professional-services']
				}
			})
		)

		build_relationship_site(collections: %w[clients industries projects], relationships: relationships, files: files) do |site, _files|
			expect(site.collections.fetch('industries').docs.map(&:basename_without_ext)).to eq(['professional-services'])
			expect(reference_ids(document_for(site, 'clients', 'beckett-rankine').data.fetch('relationships').fetch('industries'))).to eq(['industries/professional-services'])
		end
	end

	it 'leaves separate ingestion paths untouched with the configured primary path after seed-graph resolution' do
		define_resolver('PrimaryPathClientIndustryAncestors', from: 'clients', to: 'industries') do
			def resolve
				relationships.each do |industry|
					ancestors(industry).each do |ancestor|
						link(ancestor, reference: { 'distance' => ancestor.fetch('distance') }, persist: true)
					end
				end
			end
		end

		relationships = {
			'frontmatter' => {
				'base' => '',
				'primary' => 'meta.id',
				'foreign' => 'data.<collection>',
				'output' => 'meta.links.<collection>'
			},
			'tree' => {
				'frontmatter' => {
					'parent' => 'meta.parent'
				}
			},
			'relationships' => [
				{ 'from' => 'clients', 'to' => 'industries' },
				{ 'from' => 'industries', 'to' => 'self', 'mode' => 'parent' },
				{
					'from' => 'projects',
					'to' => 'industries',
					'prune' => {
						'mode' => 'inverse',
						'min' => 1
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('clients', 'beckett-rankine', {
				'meta' => {
					'id' => 'client-beckett-rankine'
				},
				'data' => {
					'industries' => [
						{
							'id' => 'industry-architecture',
							'slug' => 'architecture',
							'title' => 'Architecture',
							'type' => 'industry'
						}
					]
				}
			}),
			collection_document('industries', 'professional-services', {
				'meta' => {
					'id' => 'industry-professional-services'
				}
			}),
			collection_document('industries', 'architecture', {
				'meta' => {
					'id' => 'industry-architecture',
					'parent' => 'industry-professional-services'
				}
			}),
			collection_document('projects', 'proof', {
				'meta' => {
					'id' => 'project-proof'
				},
				'data' => {
					'industries' => ['industry-professional-services']
				}
			})
		)

		build_relationship_site(collections: %w[clients industries projects], relationships: relationships, files: files) do |site, _files|
			client = document_for(site, 'clients', 'beckett-rankine')
			expect(client.data.fetch('data').fetch('industries')).to eq([
				{
					'id' => 'industry-architecture',
					'slug' => 'architecture',
					'title' => 'Architecture',
					'type' => 'industry'
				}
			])
			expect(reference_ids(client.data.fetch('meta').fetch('links').fetch('industries'))).to eq(['industry-professional-services'])
		end
	end

	it 'rebuilds the tree from the updated seed after normal pruning removes a parent node' do
		relationships = {
			'prune' => {
				'tree' => {
					'orphans' => 'grandparents'
				}
			},
			'relationships' => [
				{ 'from' => 'categories', 'to' => 'self', 'mode' => 'parent' },
				{
					'from' => 'categories',
					'to' => 'badges',
					'prune' => {
						'min' => 1
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('categories', 'root', {
				'relationships' => {
					'badges' => ['badges/root']
				}
			}),
			collection_document('categories', 'parent', {
				'relationships' => {
					'parent' => 'categories/root'
				}
			}),
			collection_document('categories', 'child', {
				'relationships' => {
					'parent' => 'categories/parent',
					'badges' => ['badges/child']
				}
			}),
			collection_document('badges', 'root'),
			collection_document('badges', 'child')
		)

		build_relationship_site(collections: %w[categories badges], relationships: relationships, files: files) do |site, _files|
			child = document_for(site, 'categories', 'child')

			expect(site.collections.fetch('categories').docs.map(&:basename_without_ext)).to eq(%w[child root])
			expect(reference_ids(child.data.fetch('relationships').fetch('parents'))).to eq(['categories/root'])
		end
	end

	it 'only prunes root tree nodes when depth is 1' do
		relationships = {
			'prune' => {
				'tree' => {
					'orphans' => 'orphan'
				}
			},
			'relationships' => [
				{
					'from' => 'categories',
					'to' => 'self',
					'mode' => 'parent',
					'prune' => {
						'mode' => 'inverse',
						'min' => 2,
						'depth' => 1
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('categories', 'root', {
				'relationships' => {
					'child' => 'categories/child'
				}
			}),
			collection_document('categories', 'child', {
				'relationships' => {
					'child' => 'categories/leaf'
				}
			}),
			collection_document('categories', 'leaf')
		)

		build_relationship_site(collections: %w[categories], relationships: relationships, files: files) do |site, _files|
			expect(site.collections.fetch('categories').docs).to eq([])
		end
	end

	it 'prunes exact frontmatter matches and contracts consecutive removed tree nodes' do
		relationships = {
			'relationships' => [
				{
					'from' => 'pages',
					'to' => 'self',
					'mode' => 'parent',
					'prune' => {
						'where' => {
							'exists' => false
						}
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('pages', 'root', { 'exists' => true }),
			collection_document('pages', 'removed-a', {
				'exists' => false,
				'relationships' => {
					'parent' => 'pages/root'
				}
			}),
			collection_document('pages', 'removed-b', {
				'exists' => false,
				'relationships' => {
					'parent' => 'pages/removed-a'
				}
			}),
			collection_document('pages', 'leaf', {
				'relationships' => {
					'parent' => 'pages/removed-b'
				}
			}),
			collection_document('pages', 'string-false', {
				'exists' => 'false',
				'relationships' => {
					'parent' => 'pages/root'
				}
			})
		)

		build_relationship_site(collections: %w[pages], relationships: relationships, files: files) do |site, _files|
			leaf = document_for(site, 'pages', 'leaf')

			expect(site.collections.fetch('pages').docs.map(&:basename_without_ext)).to eq(%w[leaf root string-false])
			expect(reference_ids(leaf.data.fetch('relationships').fetch('parents'))).to eq(['pages/root'])
		end
	end

	it 'matches nested frontmatter with AND and distinguishes null from missing' do
		relationships = {
			'relationships' => [
				{
					'from' => 'pages',
					'to' => 'self',
					'mode' => 'parent',
					'prune' => {
						'where' => {
							'meta.status' => 'hidden',
							'meta.reason' => nil
						}
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('pages', 'matching', {
				'meta' => {
					'status' => 'hidden',
					'reason' => nil
				}
			}),
			collection_document('pages', 'missing-reason', {
				'meta' => {
					'status' => 'hidden'
				}
			}),
			collection_document('pages', 'visible', {
				'meta' => {
					'status' => 'visible',
					'reason' => nil
				}
			})
		)

		build_relationship_site(collections: %w[pages], relationships: relationships, files: files) do |site, _files|
			expect(site.collections.fetch('pages').docs.map(&:basename_without_ext)).to eq(%w[missing-reason visible])
		end
	end

	it 'applies inverse where pruning to the tree target collection' do
		relationships = {
			'relationships' => [
				{
					'from' => 'pages',
					'to' => 'sections',
					'mode' => 'parent',
					'prune' => {
						'mode' => 'inverse',
						'where' => {
							'hidden' => true
						}
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('sections', 'hidden', { 'hidden' => true }),
			collection_document('sections', 'visible', { 'hidden' => false }),
			collection_document('pages', 'child', {
				'relationships' => {
					'parent' => 'sections/hidden'
				}
			})
		)

		build_relationship_site(collections: %w[pages sections], relationships: relationships, files: files) do |site, _files|
			child = document_for(site, 'pages', 'child')

			expect(site.collections.fetch('sections').docs.map(&:basename_without_ext)).to eq(['visible'])
			expect(reference_ids(child.data.fetch('relationships').fetch('parents'))).to eq([])
		end
	end

	it 'requires both where and relationship modes to select a tree document' do
		relationships = {
			'prune' => {
				'tree' => {
					'orphans' => 'orphan'
				}
			},
			'relationships' => [
				{
					'from' => 'pages',
					'to' => 'self',
					'mode' => 'parent',
					'prune' => {
						'min' => 2,
						'depth' => -1,
						'where' => {
							'hidden' => true
						}
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('pages', 'root-a'),
			collection_document('pages', 'root-b'),
			collection_document('pages', 'selected', {
				'hidden' => true,
				'relationships' => {
					'parent' => 'pages/root-a'
				}
			}),
			collection_document('pages', 'where-mismatch', {
				'hidden' => false,
				'relationships' => {
					'parent' => 'pages/root-a'
				}
			}),
			collection_document('pages', 'count-mismatch', {
				'hidden' => true,
				'relationships' => {
					'parents' => ['pages/root-a', 'pages/root-b']
				}
			})
		)

		build_relationship_site(collections: %w[pages], relationships: relationships, files: files) do |site, _files|
			expect(site.collections.fetch('pages').docs.map(&:basename_without_ext)).to eq(%w[count-mismatch root-a root-b where-mismatch])
		end
	end

	it 'combines inverse where, child counts, and positive depth selection' do
		relationships = {
			'prune' => {
				'tree' => {
					'orphans' => 'orphan'
				}
			},
			'relationships' => [
				{
					'from' => 'pages',
					'to' => 'sections',
					'mode' => 'parent',
					'prune' => {
						'mode' => 'inverse',
						'min' => 2,
						'depth' => 1,
						'where' => {
							'hidden' => true
						}
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('sections', 'selected', { 'hidden' => true }),
			collection_document('sections', 'count-mismatch', { 'hidden' => true }),
			collection_document('sections', 'where-mismatch', { 'hidden' => false }),
			collection_document('pages', 'selected-child', {
				'relationships' => {
					'parent' => 'sections/selected'
				}
			}),
			collection_document('pages', 'count-child-a', {
				'relationships' => {
					'parent' => 'sections/count-mismatch'
				}
			}),
			collection_document('pages', 'count-child-b', {
				'relationships' => {
					'parent' => 'sections/count-mismatch'
				}
			}),
			collection_document('pages', 'where-child', {
				'relationships' => {
					'parent' => 'sections/where-mismatch'
				}
			})
		)

		build_relationship_site(collections: %w[pages sections], relationships: relationships, files: files) do |site, _files|
			selected_child = document_for(site, 'pages', 'selected-child')

			expect(site.collections.fetch('sections').docs.map(&:basename_without_ext)).to eq(%w[count-mismatch where-mismatch])
			expect(reference_ids(selected_child.data.fetch('relationships').fetch('parents'))).to eq([])
		end
	end

	it 'keeps orphan-policy behaviour when where removes a parent without ancestors' do
		expected_pages_by_mode = {
			'grandparents' => ['child'],
			'grandparents required' => [],
			'prune' => [],
			'orphan' => ['child']
		}

		expected_pages_by_mode.each do |orphan_mode, expected_pages|
			relationships = {
				'prune' => {
					'tree' => {
						'orphans' => orphan_mode
					}
				},
				'relationships' => [
					{
						'from' => 'pages',
						'to' => 'self',
						'mode' => 'parent',
						'prune' => {
							'where' => {
								'remove' => true
							}
						}
					}
				]
			}
			files = relationship_site_files(
				collection_document('pages', 'parent', { 'remove' => true }),
				collection_document('pages', 'child', {
					'relationships' => {
						'parent' => 'pages/parent'
					}
				})
			)

			build_relationship_site(collections: %w[pages], relationships: relationships, files: files) do |site, _files|
				expect(site.collections.fetch('pages').docs.map(&:basename_without_ext)).to eq(expected_pages)
				if expected_pages.include?('child')
					child = document_for(site, 'pages', 'child')
					expect(reference_ids(child.data.fetch('relationships').fetch('parents'))).to eq([])
				end
			end
		end
	end

	it 'deduplicates ordered transitive ancestors before enforcing the parent limit' do
		relationships = {
			'tree' => {
				'max' => {
					'parents' => 2
				}
			},
			'relationships' => [
				{
					'from' => 'pages',
					'to' => 'self',
					'mode' => 'parent',
					'prune' => {
						'where' => {
							'remove' => true
						}
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('pages', 'grand-a'),
			collection_document('pages', 'grand-b'),
			collection_document('pages', 'grand-c'),
			collection_document('pages', 'removed-a', {
				'remove' => true,
				'relationships' => {
					'parents' => ['pages/grand-b', 'pages/grand-a']
				}
			}),
			collection_document('pages', 'removed-b', {
				'remove' => true,
				'relationships' => {
					'parents' => ['pages/grand-b', 'pages/grand-c']
				}
			}),
			collection_document('pages', 'leaf', {
				'relationships' => {
					'parents' => ['pages/removed-a', 'pages/removed-b']
				}
			})
		)

		build_relationship_site(collections: %w[pages], relationships: relationships, files: files) do |site, _files|
			leaf = document_for(site, 'pages', 'leaf')

			expect(site.collections.fetch('pages').docs.map(&:basename_without_ext)).to eq(%w[grand-a grand-b grand-c leaf])
			expect(reference_ids(leaf.data.fetch('relationships').fetch('parents'))).to eq([
				'pages/grand-b',
				'pages/grand-a'
			])
		end
	end

	it 'preserves scoped tree identity and permalinks while contracting where matches' do
		relationships = {
			'frontmatter' => {
				'base' => '',
				'primary' => 'id',
				'scope' => 'locale'
			},
			'relationships' => [
				{
					'from' => 'pages',
					'to' => 'self',
					'mode' => 'parent',
					'prune' => {
						'where' => {
							'flags.remove' => true
						}
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('pages', 'root-en', { 'id' => 'root', 'locale' => 'en', 'permalink' => '/en/root/' }),
			collection_document('pages', 'root-fr', { 'id' => 'root', 'locale' => 'fr', 'permalink' => '/fr/root/' }),
			collection_document('pages', 'removed-en', {
				'id' => 'branch',
				'locale' => 'en',
				'parent' => 'root',
				'flags' => {
					'remove' => true
				}
			}),
			collection_document('pages', 'branch-fr', {
				'id' => 'branch',
				'locale' => 'fr',
				'parent' => 'root',
				'flags' => {
					'remove' => false
				}
			}),
			collection_document('pages', 'leaf-en', { 'id' => 'leaf', 'locale' => 'en', 'parent' => 'branch', 'permalink' => '/en/leaf/' }),
			collection_document('pages', 'leaf-fr', { 'id' => 'leaf', 'locale' => 'fr', 'parent' => 'branch', 'permalink' => '/fr/leaf/' })
		)

		build_relationship_site(collections: %w[pages], relationships: relationships, files: files) do |site, _files|
			en_leaf = document_for(site, 'pages', 'leaf-en')
			fr_leaf = document_for(site, 'pages', 'leaf-fr')
			en_parent = en_leaf.data.fetch('parents').first
			fr_parent = fr_leaf.data.fetch('parents').first

			expect(en_parent.fetch('page').basename_without_ext).to eq('root-en')
			expect(en_parent.fetch('scope')).to eq('locale' => 'en')
			expect(fr_parent.fetch('page').basename_without_ext).to eq('branch-fr')
			expect(fr_parent.fetch('scope')).to eq('locale' => 'fr')
			expect(en_leaf.url).to eq('/en/leaf/')
			expect(fr_leaf.url).to eq('/fr/leaf/')
		end
	end

	it 'contracts URL-inferred edges without changing the surviving URL' do
		relationships = {
			'tree' => {
				'url' => true
			},
			'relationships' => [
				{
					'from' => 'pages',
					'to' => 'self',
					'mode' => 'parent',
					'prune' => {
						'where' => {
							'remove' => true
						}
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('pages', 'root', { 'permalink' => '/guides/index.html' }),
			collection_document('pages', 'removed', { 'remove' => true, 'permalink' => '/guides/chapter/index.html' }),
			collection_document('pages', 'leaf', { 'permalink' => '/guides/chapter/intro/' })
		)

		build_relationship_site(collections: %w[pages], relationships: relationships, files: files) do |site, _files|
			leaf = document_for(site, 'pages', 'leaf')

			expect(reference_ids(leaf.data.fetch('relationships').fetch('parents'))).to eq(['pages/root'])
			expect(leaf.url).to eq('/guides/chapter/intro/')
		end
	end

	it 'removes where-pruned documents from normal relationship resolution' do
		relationships = {
			'relationships' => [
				{
					'from' => 'pages',
					'to' => 'self',
					'mode' => 'parent',
					'prune' => {
						'where' => {
							'archived' => true
						}
					}
				},
				{
					'from' => 'articles',
					'to' => 'pages'
				}
			]
		}

		files = relationship_site_files(
			collection_document('pages', 'kept'),
			collection_document('pages', 'removed', { 'archived' => true }),
			collection_document('articles', 'guide', {
				'relationships' => {
					'pages' => ['pages/kept', 'pages/removed']
				}
			})
		)

		build_relationship_site(collections: %w[articles pages], relationships: relationships, files: files) do |site, _files|
			article = document_for(site, 'articles', 'guide')

			expect(site.collections.fetch('pages').docs.map(&:basename_without_ext)).to eq(['kept'])
			expect(reference_ids(article.data.fetch('relationships').fetch('pages'))).to eq(['pages/kept'])
		end
	end

	it 'only prunes nodes beyond the selected tree depth when depth is negative' do
		relationships = {
			'prune' => {
				'tree' => {
					'orphans' => 'orphan'
				}
			},
			'relationships' => [
				{
					'from' => 'categories',
					'to' => 'self',
					'mode' => 'parent',
					'prune' => {
						'min' => 2,
						'depth' => -1
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('categories', 'root', {
				'relationships' => {
					'child' => 'categories/child'
				}
			}),
			collection_document('categories', 'child', {
				'relationships' => {
					'child' => 'categories/leaf'
				}
			}),
			collection_document('categories', 'leaf')
		)

		build_relationship_site(collections: %w[categories], relationships: relationships, files: files) do |site, _files|
			expect(site.collections.fetch('categories').docs.map(&:basename_without_ext)).to eq(['root'])
		end
	end

	it 'reattaches orphaned tree documents to their original grandparents in deterministic order' do
		relationships = {
			'prune' => {
				'tree' => {
					'orphans' => 'grandparents'
				}
			},
			'relationships' => [
				{ 'from' => 'categories', 'to' => 'self', 'mode' => 'parent' },
				{
					'from' => 'categories',
					'to' => 'badges',
					'prune' => {
						'min' => 1
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('categories', 'grand-a', {
				'relationships' => {
					'badges' => ['badges/grand-a']
				}
			}),
			collection_document('categories', 'grand-b', {
				'relationships' => {
					'badges' => ['badges/grand-b']
				}
			}),
			collection_document('categories', 'parent-a', {
				'relationships' => {
					'parent' => 'categories/grand-a'
				}
			}),
			collection_document('categories', 'parent-b', {
				'relationships' => {
					'parent' => 'categories/grand-b'
				}
			}),
			collection_document('categories', 'child', {
				'relationships' => {
					'parents' => ['categories/parent-b', 'categories/parent-a'],
					'badges' => ['badges/child']
				}
			}),
			collection_document('badges', 'grand-a'),
			collection_document('badges', 'grand-b'),
			collection_document('badges', 'child')
		)

		build_relationship_site(collections: %w[categories badges], relationships: relationships, files: files) do |site, _files|
			child = document_for(site, 'categories', 'child')

			expect(site.collections.fetch('categories').docs.map(&:basename_without_ext)).to eq(%w[child grand-a grand-b])
			expect(reference_ids(child.data.fetch('relationships').fetch('parents'))).to eq([
				'categories/grand-b',
				'categories/grand-a'
			])
			expect(child.data.fetch('relationships').fetch('depth')).to eq(1)
		end
	end

	it 'recalculates tree prune depth after orphan reattachment changes a node depth' do
		relationships = {
			'prune' => {
				'tree' => {
					'orphans' => 'grandparents'
				}
			},
			'relationships' => [
				{
					'from' => 'categories',
					'to' => 'self',
					'mode' => 'parent',
					'prune' => {
						'mode' => 'inverse',
						'min' => 2,
						'depth' => 2
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('categories', 'root'),
			collection_document('categories', 'branch-b', {
				'relationships' => {
					'parent' => 'categories/root'
				}
			}),
			collection_document('categories', 'branch-d', {
				'relationships' => {
					'parent' => 'categories/root'
				}
			}),
			collection_document('categories', 'branch-g', {
				'relationships' => {
					'parent' => 'categories/root'
				}
			}),
			collection_document('categories', 'leaf-c', {
				'relationships' => {
					'parent' => 'categories/branch-b'
				}
			}),
			collection_document('categories', 'leaf-d-1', {
				'relationships' => {
					'parent' => 'categories/branch-d'
				}
			}),
			collection_document('categories', 'leaf-d-2', {
				'relationships' => {
					'parent' => 'categories/branch-d'
				}
			}),
			collection_document('categories', 'leaf-g-1', {
				'relationships' => {
					'parent' => 'categories/branch-g'
				}
			}),
			collection_document('categories', 'leaf-g-2', {
				'relationships' => {
					'parent' => 'categories/branch-g'
				}
			})
		)

		build_relationship_site(collections: %w[categories], relationships: relationships, files: files) do |site, _files|
			root = document_for(site, 'categories', 'root')

			expect(site.collections.fetch('categories').docs.map(&:basename_without_ext)).to eq(%w[
				branch-d
				branch-g
				leaf-d-1
				leaf-d-2
				leaf-g-1
				leaf-g-2
				root
			])
			expect(reference_ids(root.data.fetch('relationships').fetch('children'))).to eq([
				'categories/branch-d',
				'categories/branch-g'
			])
		end
	end

	it 'prunes orphaned tree documents when grandparents are required but none survive' do
		relationships = {
			'prune' => {
				'tree' => {
					'orphans' => 'grandparents required'
				}
			},
			'relationships' => [
				{ 'from' => 'categories', 'to' => 'self', 'mode' => 'parent' },
				{
					'from' => 'categories',
					'to' => 'badges',
					'prune' => {
						'min' => 1
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('categories', 'grand'),
			collection_document('categories', 'parent', {
				'relationships' => {
					'parent' => 'categories/grand'
				}
			}),
			collection_document('categories', 'child', {
				'relationships' => {
					'parent' => 'categories/parent',
					'badges' => ['badges/child']
				}
			}),
			collection_document('badges', 'child')
		)

		build_relationship_site(collections: %w[categories badges], relationships: relationships, files: files) do |site, _files|
			expect(site.collections.fetch('categories').docs).to eq([])
		end
	end

	it 'recursively prunes orphaned tree descendants when orphan pruning is enabled' do
		relationships = {
			'prune' => {
				'tree' => {
					'orphans' => 'prune'
				}
			},
			'relationships' => [
				{ 'from' => 'categories', 'to' => 'self', 'mode' => 'parent' },
				{
					'from' => 'categories',
					'to' => 'badges',
					'prune' => {
						'min' => 1
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('categories', 'root'),
			collection_document('categories', 'branch', {
				'relationships' => {
					'parent' => 'categories/root',
					'badges' => ['badges/branch']
				}
			}),
			collection_document('categories', 'leaf', {
				'relationships' => {
					'parent' => 'categories/branch',
					'badges' => ['badges/leaf']
				}
			}),
			collection_document('badges', 'branch'),
			collection_document('badges', 'leaf')
		)

		build_relationship_site(collections: %w[categories badges], relationships: relationships, files: files) do |site, _files|
			expect(site.collections.fetch('categories').docs).to eq([])
		end
	end

	it 'promotes orphaned tree documents when orphan mode is selected' do
		relationships = {
			'prune' => {
				'tree' => {
					'orphans' => 'orphan'
				}
			},
			'relationships' => [
				{ 'from' => 'categories', 'to' => 'self', 'mode' => 'parent' },
				{
					'from' => 'categories',
					'to' => 'badges',
					'prune' => {
						'min' => 1
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('categories', 'root'),
			collection_document('categories', 'branch', {
				'relationships' => {
					'parent' => 'categories/root',
					'badges' => ['badges/branch']
				}
			}),
			collection_document('categories', 'leaf', {
				'relationships' => {
					'parent' => 'categories/branch',
					'badges' => ['badges/leaf']
				}
			}),
			collection_document('badges', 'branch'),
			collection_document('badges', 'leaf')
		)

		build_relationship_site(collections: %w[categories badges], relationships: relationships, files: files) do |site, _files|
			expect(site.collections.fetch('categories').docs.map(&:basename_without_ext)).to eq(%w[branch leaf])
			expect(document_for(site, 'categories', 'branch').data.fetch('relationships').fetch('parents')).to eq([])
			expect(reference_ids(document_for(site, 'categories', 'leaf').data.fetch('relationships').fetch('parents'))).to eq(['categories/branch'])
		end
	end

	it 'stops pruning at the configured iteration cap while preserving the surviving in-memory graph' do
		define_resolver('CappedAncestorServiceLinker', from: 'pages', to: 'services') do
			def resolve
				ancestors.each do |ancestor|
					relationships(ancestor, to: 'services').each do |service|
						link(service, persist: true)
					end
				end
			end
		end

		relationships = {
			'prune' => {
				'iterations' => 0
			},
			'relationships' => [
				{ 'from' => 'pages', 'to' => 'self', 'mode' => 'parent' },
				{
					'from' => 'pages',
					'to' => 'services',
					'prune' => {
						'min' => 1
					}
				},
				{
					'from' => 'pages',
					'to' => 'badges',
					'prune' => {
						'min' => 1
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('pages', 'root', {
				'relationships' => {
					'services' => ['services/root']
				}
			}),
			collection_document('pages', 'leaf', {
				'relationships' => {
					'parent' => 'pages/root',
					'badges' => ['badges/leaf']
				}
			}),
			collection_document('services', 'root'),
			collection_document('badges', 'leaf')
		)

		build_relationship_site(collections: %w[pages services badges], relationships: relationships, files: files) do |site, _files|
			expect(site.collections.fetch('pages').docs.map(&:basename_without_ext)).to eq(['leaf'])
			expect(reference_ids(document_for(site, 'pages', 'leaf').data.fetch('relationships').fetch('services'))).to eq(['services/root'])
		end
	end

	it 'logs the default relationship, pruning, and timing summaries' do
		relationships = {
			'relationships' => [
				{
					'from' => 'products',
					'to' => 'categories',
					'prune' => {
						'min' => 1
					}
				},
				{
					'from' => 'articles',
					'to' => 'tags'
				}
			]
		}

		files = relationship_site_files(
			collection_document('articles', 'alpha', {
				'relationships' => {
					'tags' => ['tags/news']
				}
			}),
			collection_document('products', 'alpha', {
				'relationships' => {
					'categories' => ['categories/one']
				}
			}),
			collection_document('categories', 'one'),
			collection_document('tags', 'news')
		)

		log_messages = capture_relationship_logs do
			build_relationship_site(collections: %w[articles products categories tags], relationships: relationships, files: files) do |_site, _files|
				nil
			end
		end

		expect(log_messages).to include('2 relationships defined.')
		expect(log_messages).to include("├─ articles#{Jekyll::Plugins::Relationships::RunLogger::NON_BREAKING_SPACE}→ tags (1 linked to 1)")
		expect(log_messages).to include("└─ products#{Jekyll::Plugins::Relationships::RunLogger::NON_BREAKING_SPACE}→ categories (1 linked to 1)")
		expect(log_messages).to include('Removed 0 items because of pruning rules.')
		expect(log_messages).to include(a_string_matching(/\ADone in \d+\.\d{2} seconds\.\z/))
	end

	it 'truncates removed filenames in the pruning summary without splitting names' do
		first_name = 'a' * 17
		second_name = 'b' * 26
		third_name = 'cc'
		relationships = {
			'relationships' => [
				{
					'from' => 'products',
					'to' => 'categories',
					'prune' => {
						'min' => 1
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('products', first_name),
			collection_document('products', second_name),
			collection_document('products', third_name)
		)

		log_messages = capture_relationship_logs do
			build_relationship_site(collections: %w[products categories], relationships: relationships, files: files) do |_site, _files|
				nil
			end
		end

		expect(log_messages).to include('Removed 3 items because of pruning rules.')
		expect(log_messages).to include("└─ products:#{Jekyll::Plugins::Relationships::RunLogger::NON_BREAKING_SPACE}3 removed (#{first_name}.md, #{second_name}.md, ...)")
		expect(log_messages.join("\n")).not_to include("#{third_name}.md")
	end
end
