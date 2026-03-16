# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'tree relationships' do
	it 'builds tree links and calculates shortest ancestor distances' do
		relationships = {
			'relationships' => [
				{ 'from' => 'deliverables', 'to' => 'self', 'mode' => 'parent' }
			]
		}

		files = relationship_site_files(
			collection_document('deliverables', 'root'),
			collection_document('deliverables', 'branch-a', {
				'relationships' => {
					'parent' => 'deliverables/root'
				}
			}),
			collection_document('deliverables', 'branch-b', {
				'relationships' => {
					'parent' => 'deliverables/root'
				}
			}),
			collection_document('deliverables', 'leaf', {
				'relationships' => {
					'parents' => ['deliverables/branch-a', 'deliverables/branch-b']
				}
			})
		)

		build_relationship_site(collections: %w[deliverables], relationships: relationships, files: files) do |site, _files|
			leaf = document_for(site, 'deliverables', 'leaf')
			ancestors = leaf.data.fetch('relationships').fetch('ancestors')

			expect(reference_ids(leaf.data.fetch('relationships').fetch('parents'))).to eq([
				'deliverables/branch-a',
				'deliverables/branch-b'
			])
			expect(ancestors.map { |reference| [reference.fetch('id'), reference.fetch('distance')] }).to eq([
				['deliverables/leaf', 0],
				['deliverables/branch-a', 1],
				['deliverables/branch-b', 1],
				['deliverables/root', 2]
			])
		end
	end

	it 'accumulates edges declared from both parent and child sides' do
		relationships = {
			'relationships' => [
				{ 'from' => 'categories', 'to' => 'self', 'mode' => 'parent' }
			]
		}

		files = relationship_site_files(
			collection_document('categories', 'root', {
				'relationships' => {
					'child' => 'categories/branch'
				}
			}),
			collection_document('categories', 'branch'),
			collection_document('categories', 'leaf', {
				'relationships' => {
					'parent' => 'categories/branch'
				}
			})
		)

		build_relationship_site(collections: %w[categories], relationships: relationships, files: files) do |site, _files|
			root = document_for(site, 'categories', 'root')
			branch = document_for(site, 'categories', 'branch')
			leaf = document_for(site, 'categories', 'leaf')

			expect(reference_ids(root.data.fetch('relationships').fetch('children'))).to eq(['categories/branch'])
			expect(reference_ids(branch.data.fetch('relationships').fetch('parents'))).to eq(['categories/root'])
			expect(reference_ids(branch.data.fetch('relationships').fetch('children'))).to eq(['categories/leaf'])
			expect(reference_ids(leaf.data.fetch('relationships').fetch('parents'))).to eq(['categories/branch'])
		end
	end

	it 'supports cross-collection trees when the mode allows the from collection to parent the to collection' do
		relationships = {
			'relationships' => [
				{ 'from' => 'sections', 'to' => 'pages', 'mode' => 'child' }
			]
		}

		files = relationship_site_files(
			collection_document('sections', 'guides', {
				'relationships' => {
					'child' => 'pages/intro'
				}
			}),
			collection_document('pages', 'intro')
		)

		build_relationship_site(collections: %w[sections pages], relationships: relationships, files: files) do |site, _files|
			section = document_for(site, 'sections', 'guides')
			page = document_for(site, 'pages', 'intro')

			expect(reference_ids(section.data.fetch('relationships').fetch('children'))).to eq(['pages/intro'])
			expect(reference_ids(page.data.fetch('relationships').fetch('parents'))).to eq(['sections/guides'])
		end
	end

	it 'uses singular parent and child outputs when the configured maxima are one' do
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

		files = relationship_site_files(
			collection_document('categories', 'root', {
				'relationships' => {
					'child' => 'categories/leaf'
				}
			}),
			collection_document('categories', 'leaf')
		)

		build_relationship_site(collections: %w[categories], relationships: relationships, files: files) do |site, _files|
			root = document_for(site, 'categories', 'root')
			leaf = document_for(site, 'categories', 'leaf')

			expect(root.data.fetch('relationships').fetch('child').fetch('id')).to eq('categories/leaf')
			expect(leaf.data.fetch('relationships').fetch('parent').fetch('id')).to eq('categories/root')
		end
	end

	it 'keeps only the first parent when the maximum parent count is reached' do
		relationships = {
			'tree' => {
				'max' => {
					'parents' => 1
				}
			},
			'relationships' => [
				{ 'from' => 'categories', 'to' => 'self', 'mode' => 'parent' }
			]
		}

		files = relationship_site_files(
			collection_document('categories', 'alpha'),
			collection_document('categories', 'beta'),
			collection_document('categories', 'leaf', {
				'relationships' => {
					'parent' => ['categories/alpha', 'categories/beta']
				}
			})
		)

		build_relationship_site(collections: %w[categories], relationships: relationships, files: files) do |site, _files|
			alpha = document_for(site, 'categories', 'alpha')
			beta = document_for(site, 'categories', 'beta')
			leaf = document_for(site, 'categories', 'leaf')

			expect(leaf.data.fetch('relationships').fetch('parent').fetch('id')).to eq('categories/alpha')
			expect(reference_ids(alpha.data.fetch('relationships').fetch('children'))).to eq(['categories/leaf'])
			expect(beta.data.fetch('relationships').fetch('children')).to eq([])
		end
	end

	it 'ignores self-referential tree links' do
		relationships = {
			'relationships' => [
				{ 'from' => 'categories', 'to' => 'self', 'mode' => 'parent' }
			]
		}

		files = relationship_site_files(
			collection_document('categories', 'alpha', {
				'relationships' => {
					'parent' => 'categories/alpha'
				}
			})
		)

		build_relationship_site(collections: %w[categories], relationships: relationships, files: files) do |site, _files|
			category = document_for(site, 'categories', 'alpha')

			expect(category.data.fetch('relationships').fetch('parents')).to eq([])
			expect(category.data.fetch('relationships').fetch('children')).to eq([])
			expect(reference_ids(category.data.fetch('relationships').fetch('ancestors'))).to eq(['categories/alpha'])
		end
	end

	it 'breaks loops by rejecting the edge that would complete the cycle' do
		relationships = {
			'relationships' => [
				{ 'from' => 'categories', 'to' => 'self', 'mode' => 'parent' }
			]
		}

		files = relationship_site_files(
			collection_document('categories', 'alpha', {
				'relationships' => {
					'parent' => 'categories/beta'
				}
			}),
			collection_document('categories', 'beta', {
				'relationships' => {
					'parent' => 'categories/alpha'
				}
			})
		)

		build_relationship_site(collections: %w[categories], relationships: relationships, files: files) do |site, _files|
			alpha = document_for(site, 'categories', 'alpha')
			beta = document_for(site, 'categories', 'beta')

			expect(reference_ids(alpha.data.fetch('relationships').fetch('parents'))).to eq(['categories/beta'])
			expect(beta.data.fetch('relationships').fetch('parents')).to eq([])
			expect(reference_ids(beta.data.fetch('relationships').fetch('children'))).to eq(['categories/alpha'])
		end
	end

	it 'infers tree parents from normalised URLs when URL mode is enabled' do
		relationships = {
			'tree' => {
				'url' => true
			},
			'relationships' => [
				{ 'from' => 'pages', 'to' => 'self', 'mode' => 'parent' }
			]
		}

		files = relationship_site_files(
			collection_document('pages', 'guides', {
				'permalink' => '/guides/index.html'
			}),
			collection_document('pages', 'intro', {
				'permalink' => '/guides/intro/'
			})
		)

		build_relationship_site(collections: %w[pages], relationships: relationships, files: files) do |site, _files|
			intro = document_for(site, 'pages', 'intro')
			expect(reference_ids(intro.data.fetch('relationships').fetch('parents'))).to eq(['pages/guides'])
		end
	end

	it 'uses custom tree frontmatter paths under the configured base' do
		relationships = {
			'frontmatter' => {
				'base' => 'data'
			},
			'tree' => {
				'frontmatter' => {
					'parent' => 'up',
					'parents' => 'all_up',
					'child' => 'down',
					'children' => 'all_down',
					'ancestors' => 'lineage',
					'descendants' => 'branches'
				}
			},
			'relationships' => [
				{ 'from' => 'topics', 'to' => 'self', 'mode' => 'parent' }
			]
		}

		files = relationship_site_files(
			collection_document('topics', 'root', {
				'data' => {
					'down' => 'topics/leaf'
				}
			}),
			collection_document('topics', 'leaf')
		)

		build_relationship_site(collections: %w[topics], relationships: relationships, files: files) do |site, _files|
			root = document_for(site, 'topics', 'root')
			leaf = document_for(site, 'topics', 'leaf')

			expect(reference_ids(root.data.fetch('data').fetch('all_down'))).to eq(['topics/leaf'])
			expect(reference_ids(leaf.data.fetch('data').fetch('all_up'))).to eq(['topics/root'])
			expect(reference_ids(leaf.data.fetch('data').fetch('lineage'))).to eq(['topics/leaf', 'topics/root'])
			expect(reference_ids(root.data.fetch('data').fetch('branches'))).to eq(['topics/root', 'topics/leaf'])
		end
	end
end
