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
