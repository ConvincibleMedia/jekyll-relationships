# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'relationship resolvers' do
	it 'adds links idempotently when the same target is linked more than once' do
		define_resolver('IdempotentAdder', from: 'projects', to: 'services') do
			def resolve
				link('services/design')
				link('services/design')
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha'),
			collection_document('services', 'design')
		)

		build_relationship_site(collections: %w[projects services], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			expect(reference_ids(project.data.fetch('relationships').fetch('services'))).to eq(['services/design'])
		end
	end

	it 'can remove one specific link from the current relationship' do
		define_resolver('SpecificUnlinker', from: 'projects', to: 'services') do
			def resolve
				unlink('services/design')
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'relationships' => {
					'services' => ['services/design', 'services/build']
				}
			}),
			collection_document('services', 'design'),
			collection_document('services', 'build')
		)

		build_relationship_site(collections: %w[projects services], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			expect(reference_ids(project.data.fetch('relationships').fetch('services'))).to eq(['services/build'])
		end
	end

	it 'can clear all links from the current relationship with unlink and no reference' do
		define_resolver('ClearAllLinks', from: 'projects', to: 'services') do
			def resolve
				unlink
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'relationships' => {
					'services' => ['services/design', 'services/build']
				}
			}),
			collection_document('services', 'design'),
			collection_document('services', 'build')
		)

		build_relationship_site(collections: %w[projects services], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			expect(project.data.fetch('relationships').fetch('services')).to eq([])
		end
	end

	it 'can inspect the current link state while resolving and build on top of it' do
		define_resolver('CurrentStateReader', from: 'projects', to: 'services') do
			def resolve
				link('services/build') if relationships.length == 1
				link('services/research') if relationships.length == 2
			end
		end

		relationships = {
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
			collection_document('services', 'design'),
			collection_document('services', 'build'),
			collection_document('services', 'research')
		)

		build_relationship_site(collections: %w[projects services], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			expect(reference_ids(project.data.fetch('relationships').fetch('services'))).to eq([
				'services/design',
				'services/build',
				'services/research'
			])
		end
	end

	it 'returns the current document without forcing recursive self-resolution' do
		define_resolver('CurrentDocumentGuard', from: 'projects', to: 'services') do
			def resolve
				current_document = document
				link('services/design') if current_document == @document
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha'),
			collection_document('services', 'design')
		)

		build_relationship_site(collections: %w[projects services], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			expect(reference_ids(project.data.fetch('relationships').fetch('services'))).to eq(['services/design'])
		end
	end

	it 'can recurse into linked items and resolve their normal relationships first' do
		define_resolver('ProjectInheritedServices', from: 'projects', to: 'services') do
			def resolve
				relationships(to: 'clients').each do |client|
					document(client)
					relationships(client, to: 'services').each do |service|
						link(service)
					end
				end
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'clients', 'to' => 'services' },
				{ 'from' => 'projects', 'to' => 'clients' },
				{ 'from' => 'projects', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('clients', 'acme', {
				'relationships' => {
					'services' => ['services/design']
				}
			}),
			collection_document('projects', 'alpha', {
				'relationships' => {
					'clients' => ['clients/acme']
				}
			}),
			collection_document('services', 'design')
		)

		build_relationship_site(collections: %w[clients projects services], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			expect(reference_ids(project.data.fetch('relationships').fetch('services'))).to eq(['services/design'])
		end
	end

	it 'can traverse tree ancestry while resolving a normal relationship' do
		define_resolver('ProjectServicesFromDeliverables', from: 'projects', to: 'services') do
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

		files = relationship_site_files(
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

		build_relationship_site(collections: %w[deliverables projects services], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			services = project.data.fetch('relationships').fetch('services')

			expect(reference_ids(services)).to eq(['services/design'])
			expect(services.first.fetch('distance')).to eq(1)
		end
	end

	it 'detects cyclic resolver dependencies between normal relationships' do
		define_resolver('CategoriesNeedServices', from: 'products', to: 'categories') do
			def resolve
				relationships(to: 'services')
			end
		end

		define_resolver('ServicesNeedCategories', from: 'products', to: 'services') do
			def resolve
				relationships(to: 'categories')
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'products', 'to' => 'categories, services' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'alpha'),
			collection_document('categories', 'one'),
			collection_document('services', 'design')
		)

		expect do
			build_relationship_site(collections: %w[products categories services], relationships: relationships, files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /cyclic relationship resolution/i)
	end

	it 'expands resolver from and to selectors with the same collection-keyword rules as relationships' do
		define_resolver('SelfResolverExpansion', from: 'products, categories', to: 'self') do
			def resolve
				if @from == 'products'
					link('products/shared')
				else
					link('categories/shared')
				end
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'products, categories', 'to' => 'self' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'alpha', {
				'relationships' => {
					'products' => ['products/beta']
				}
			}),
			collection_document('products', 'beta'),
			collection_document('products', 'shared'),
			collection_document('categories', 'one', {
				'relationships' => {
					'categories' => ['categories/two']
				}
			}),
			collection_document('categories', 'two'),
			collection_document('categories', 'shared')
		)

		build_relationship_site(collections: %w[products categories], relationships: relationships, files: files) do |site, _files|
			product = document_for(site, 'products', 'alpha')
			category = document_for(site, 'categories', 'one')

			expect(reference_ids(product.data.fetch('relationships').fetch('products'))).to eq(['products/beta', 'products/shared'])
			expect(reference_ids(category.data.fetch('relationships').fetch('categories'))).to eq(['categories/two', 'categories/shared'])
		end
	end

	it 'uses the from helper hint to disambiguate helper references by collection' do
		define_resolver('DisambiguatedLookup', from: 'projects', to: 'services') do
			def resolve
				link(document('shared', from: 'services'))
			end
		end

		relationships = {
			'frontmatter' => {
				'base' => '',
				'primary' => 'id'
			},
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'services' },
				{ 'from' => 'projects', 'to' => 'categories' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', { 'id' => 'project-alpha' }),
			collection_document('services', 'design', { 'id' => 'shared' }),
			collection_document('categories', 'one', { 'id' => 'shared' })
		)

		build_relationship_site(collections: %w[projects services categories], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			expect(reference_ids(project.data.fetch('services'))).to eq(['shared'])
		end
	end
end
