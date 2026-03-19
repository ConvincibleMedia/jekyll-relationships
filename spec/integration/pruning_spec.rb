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

	it 'reruns normal resolvers after pruning changes the active tree' do
		define_resolver('AncestorServiceLinker', from: 'pages', to: 'services') do
			def resolve
				ancestors.each do |ancestor|
					relationships(ancestor, to: 'services').each do |service|
						link(service)
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
			expect(reference_ids(document_for(site, 'pages', 'leaf').data.fetch('relationships').fetch('services'))).to eq(['services/branch'])
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
			expect(site.collections.fetch('categories').docs.map(&:basename_without_ext)).to eq(%w[child leaf])
			expect(document_for(site, 'categories', 'child').data.fetch('relationships').fetch('parents')).to eq([])
			expect(reference_ids(document_for(site, 'categories', 'child').data.fetch('relationships').fetch('children'))).to eq(['categories/leaf'])
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
			expect(site.collections.fetch('categories').docs.map(&:basename_without_ext)).to eq(%w[child grand-a grand-b])
			expect(reference_ids(document_for(site, 'categories', 'child').data.fetch('relationships').fetch('parents'))).to eq([
				'categories/grand-b',
				'categories/grand-a'
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

	it 'stops pruning at the configured iteration cap but still rebuilds the final graph' do
		define_resolver('CappedAncestorServiceLinker', from: 'pages', to: 'services') do
			def resolve
				ancestors.each do |ancestor|
					relationships(ancestor, to: 'services').each do |service|
						link(service)
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
			expect(document_for(site, 'pages', 'leaf').data.fetch('relationships').fetch('services')).to eq([])
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
		expect(log_messages).to include('├─ articles → tags (1 linked to 1)')
		expect(log_messages).to include('└─ products → categories (1 linked to 1)')
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
		expect(log_messages).to include("└─ products:\u00a0 3 removed (#{first_name}.md, #{second_name}.md, ...)")
		expect(log_messages.join("\n")).not_to include("#{third_name}.md")
	end
end
