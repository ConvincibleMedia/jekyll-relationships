# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'relationship resolvers' do
	it 'counts repeated resolver links when the same target is linked more than once' do
		define_resolver('IdempotentAdder', from: 'projects', to: 'services') do
			def resolve
				link('services/design')
				link('services/design')
			end
		end

		relationships = {
			'multiple' => 'count',
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
			references = project.data.fetch('relationships').fetch('services')

			expect(reference_ids(references)).to eq(['services/design'])
			expect(reference_values(references, 'count')).to eq([2])
		end
	end

	it 'drops repeated resolver links in drop mode' do
		define_resolver('DroppedDuplicateAdder', from: 'projects', to: 'services') do
			def resolve
				link('services/design')
				link('services/design')
			end
		end

		relationships = {
			'multiple' => 'drop',
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
			references = project.data.fetch('relationships').fetch('services')

			expect(reference_ids(references)).to eq(['services/design'])
			expect(references).to all(satisfy { |reference| !reference.key?('count') })
		end
	end

	it 'keeps repeated resolver links in keep mode and unlinks all occurrences together' do
		define_resolver('KeepModeCycle', from: 'projects', to: 'services') do
			def resolve
				link('services/design')
				link('services/design')
				unlink('services/design')
				link('services/build')
				link('services/build')
			end
		end

		relationships = {
			'multiple' => 'keep',
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha'),
			collection_document('services', 'design'),
			collection_document('services', 'build')
		)

		build_relationship_site(collections: %w[projects services], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			references = project.data.fetch('relationships').fetch('services')

			expect(reference_ids(references)).to eq(['services/build', 'services/build'])
			expect(references).to all(satisfy { |reference| !reference.key?('count') })
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

	it 'can keep a persisted resolver link after the intermediary document is pruned in a later round' do
		define_resolver('ProjectServicesViaClientsPersisted', from: 'projects', to: 'services') do
			def resolve
				relationships(to: 'clients').each do |client|
					relationships(client, to: 'services').each do |service|
						link(service, persist: true)
					end
				end
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'clients', 'to' => 'services' },
				{
					'from' => 'clients',
					'to' => 'badges',
					'prune' => {
						'min' => 1
					}
				},
				{ 'from' => 'projects', 'to' => 'clients' },
				{
					'from' => 'projects',
					'to' => 'services',
					'prune' => {
						'min' => 1
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'relationships' => {
					'clients' => ['clients/acme']
				}
			}),
			collection_document('clients', 'acme', {
				'relationships' => {
					'services' => ['services/design']
				}
			}),
			collection_document('services', 'design')
		)

		build_relationship_site(collections: %w[projects clients services badges], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')

			expect(site.collections.fetch('clients').docs).to eq([])
			expect(site.collections.fetch('projects').docs.map(&:basename_without_ext)).to eq(['alpha'])
			expect(reference_ids(project.data.fetch('relationships').fetch('services'))).to eq(['services/design'])
		end
	end

	it 'can use a global resolver persistence default for link calls' do
		Jekyll::Plugins::Relationships::Resolvers.persist(true)

		define_resolver('ProjectServicesViaClientsGlobalPersistDefault', from: 'projects', to: 'services') do
			def resolve
				relationships(to: 'clients').each do |client|
					relationships(client, to: 'services').each do |service|
						link(service)
					end
				end
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'clients', 'to' => 'services' },
				{
					'from' => 'clients',
					'to' => 'badges',
					'prune' => {
						'min' => 1
					}
				},
				{ 'from' => 'projects', 'to' => 'clients' },
				{
					'from' => 'projects',
					'to' => 'services',
					'prune' => {
						'min' => 1
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'relationships' => {
					'clients' => ['clients/acme']
				}
			}),
			collection_document('clients', 'acme', {
				'relationships' => {
					'services' => ['services/design']
				}
			}),
			collection_document('services', 'design')
		)

		build_relationship_site(collections: %w[projects clients services badges], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')

			expect(site.collections.fetch('clients').docs).to eq([])
			expect(site.collections.fetch('projects').docs.map(&:basename_without_ext)).to eq(['alpha'])
			expect(reference_ids(project.data.fetch('relationships').fetch('services'))).to eq(['services/design'])
		end
	end

	it 'can use a resolver-class persistence default for link calls in that resolver only' do
		define_resolver('ProjectServicesViaClientsClassPersistDefault', from: 'projects', to: 'services') do
			persist true

			def resolve
				relationships(to: 'clients').each do |client|
					relationships(client, to: 'services').each do |service|
						link(service)
					end
				end
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'clients', 'to' => 'services' },
				{
					'from' => 'clients',
					'to' => 'badges',
					'prune' => {
						'min' => 1
					}
				},
				{ 'from' => 'projects', 'to' => 'clients' },
				{
					'from' => 'projects',
					'to' => 'services',
					'prune' => {
						'min' => 1
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'relationships' => {
					'clients' => ['clients/acme']
				}
			}),
			collection_document('clients', 'acme', {
				'relationships' => {
					'services' => ['services/design']
				}
			}),
			collection_document('services', 'design')
		)

		build_relationship_site(collections: %w[projects clients services badges], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')

			expect(site.collections.fetch('clients').docs).to eq([])
			expect(site.collections.fetch('projects').docs.map(&:basename_without_ext)).to eq(['alpha'])
			expect(reference_ids(project.data.fetch('relationships').fetch('services'))).to eq(['services/design'])
		end
	end

	it 'lets a resolver-class persistence default override a global resolver default' do
		Jekyll::Plugins::Relationships::Resolvers.persist(true)

		define_resolver('ProjectServicesViaClientsLocalPersistOverride', from: 'projects', to: 'services') do
			persist false

			def resolve
				relationships(to: 'clients').each do |client|
					relationships(client, to: 'services').each do |service|
						link(service)
					end
				end
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'clients', 'to' => 'services' },
				{
					'from' => 'clients',
					'to' => 'badges',
					'prune' => {
						'min' => 1
					}
				},
				{ 'from' => 'projects', 'to' => 'clients' },
				{
					'from' => 'projects',
					'to' => 'services',
					'prune' => {
						'min' => 1
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'relationships' => {
					'clients' => ['clients/acme']
				}
			}),
			collection_document('clients', 'acme', {
				'relationships' => {
					'services' => ['services/design']
				}
			}),
			collection_document('services', 'design')
		)

		build_relationship_site(collections: %w[projects clients services badges], relationships: relationships, files: files) do |site, _files|
			expect(site.collections.fetch('clients').docs).to eq([])
			expect(site.collections.fetch('projects').docs).to eq([])
		end
	end

	it 'does not duplicate a persisted link when the resolver naturally recreates it in a later round' do
		define_resolver('ProjectServicesViaClientsPersistedKeepMode', from: 'projects', to: 'services') do
			def resolve
				relationships(to: 'clients').each do |client|
					relationships(client, to: 'services').each do |service|
						link(service, persist: true)
					end
				end
			end
		end

		relationships = {
			'multiple' => 'keep',
			'relationships' => [
				{ 'from' => 'clients', 'to' => 'services' },
				{
					'from' => 'clients',
					'to' => 'badges',
					'prune' => {
						'min' => 1
					}
				},
				{ 'from' => 'projects', 'to' => 'clients' },
				{ 'from' => 'projects', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'relationships' => {
					'clients' => ['clients/kept']
				}
			}),
			collection_document('clients', 'kept', {
				'relationships' => {
					'services' => ['services/design'],
					'badges' => ['badges/active']
				}
			}),
			collection_document('clients', 'pruned'),
			collection_document('services', 'design'),
			collection_document('badges', 'active')
		)

		build_relationship_site(collections: %w[projects clients services badges], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')

			expect(site.collections.fetch('clients').docs.map(&:basename_without_ext)).to eq(['kept'])
			expect(reference_ids(project.data.fetch('relationships').fetch('services'))).to eq(['services/design'])
		end
	end

	it 'stops reapplying a persisted link after an explicit unlink clears it' do
		define_resolver('ProjectServicesPersistedThenCleared', from: 'projects', to: 'services') do
			def resolve
				relationships(to: 'clients').each do |client|
					relationships(client, to: 'services').each do |service|
						link(service, persist: true)
					end
				end
				unlink('services/design') if relationships(to: 'clients').empty?
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'clients', 'to' => 'services' },
				{
					'from' => 'clients',
					'to' => 'badges',
					'prune' => {
						'min' => 1
					}
				},
				{ 'from' => 'projects', 'to' => 'clients' },
				{ 'from' => 'projects', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'relationships' => {
					'clients' => ['clients/acme']
				}
			}),
			collection_document('clients', 'acme', {
				'relationships' => {
					'services' => ['services/design']
				}
			}),
			collection_document('services', 'design')
		)

		build_relationship_site(collections: %w[projects clients services badges], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')

			expect(site.collections.fetch('clients').docs).to eq([])
			expect(project.data.fetch('relationships').fetch('services')).to eq([])
		end
	end

	it 'reapplies a missing persisted link near its earlier proportional position' do
		define_resolver('ProjectServicesSelectivePersistence', from: 'projects', to: 'services') do
			def resolve
				relationships(to: 'clients').each do |client|
					relationships(client, to: 'services').each do |service|
						link(service, persist: service.fetch('id') == 'services/centre')
					end
				end
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'clients', 'to' => 'services' },
				{
					'from' => 'clients',
					'to' => 'badges',
					'prune' => {
						'min' => 1
					}
				},
				{ 'from' => 'projects', 'to' => 'clients' },
				{ 'from' => 'projects', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'relationships' => {
					'clients' => ['clients/left', 'clients/centre', 'clients/right']
				}
			}),
			collection_document('clients', 'left', {
				'relationships' => {
					'services' => ['services/left'],
					'badges' => ['badges/active']
				}
			}),
			collection_document('clients', 'centre', {
				'relationships' => {
					'services' => ['services/centre']
				}
			}),
			collection_document('clients', 'right', {
				'relationships' => {
					'services' => ['services/right'],
					'badges' => ['badges/active']
				}
			}),
			collection_document('services', 'left'),
			collection_document('services', 'centre'),
			collection_document('services', 'right'),
			collection_document('badges', 'active')
		)

		build_relationship_site(collections: %w[projects clients services badges], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')

			expect(site.collections.fetch('clients').docs.map(&:basename_without_ext)).to eq(%w[left right])
			expect(reference_ids(project.data.fetch('relationships').fetch('services'))).to eq([
				'services/left',
				'services/centre',
				'services/right'
			])
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

	it 'raises when a resolver requests relationships that are not defined for the current collection' do
		define_resolver('UndefinedRelationshipReader', from: 'projects', to: 'services') do
			def resolve
				relationships(to: 'clients')
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha'),
			collection_document('services', 'design'),
			collection_document('clients', 'acme')
		)

		expect do
			build_relationship_site(collections: %w[projects services clients], relationships: relationships, files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /no relationship is defined from collection `projects` to `clients`/i)
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

	it 'returns foreign relationships after the final count sorting pass' do
		define_resolver('ProjectServicesFromClients', from: 'projects', to: 'services') do
			def resolve
				relationships(to: 'clients').each do |client|
					relationships(client, to: 'services').each do |service|
						link(service)
					end
				end
			end
		end

		relationships = {
			'multiple' => {
				'mode' => 'count',
				'sort' => 'desc'
			},
			'relationships' => [
				{ 'from' => 'clients', 'to' => 'services' },
				{ 'from' => 'projects', 'to' => 'clients' },
				{ 'from' => 'projects', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('clients', 'acme', {
				'relationships' => {
					'services' => [
						'services/design',
						'services/build',
						'services/design',
						'services/research',
						'services/design',
						'services/build'
					]
				}
			}),
			collection_document('projects', 'alpha', {
				'relationships' => {
					'clients' => ['clients/acme']
				}
			}),
			collection_document('services', 'design'),
			collection_document('services', 'build'),
			collection_document('services', 'research')
		)

		build_relationship_site(collections: %w[clients projects services], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			references = project.data.fetch('relationships').fetch('services')

			expect(reference_ids(references)).to eq(['services/design', 'services/build', 'services/research'])
			expect(reference_values(references, 'count')).to eq([1, 1, 1])
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

	it 'supports parent, child, and descendant tree helper methods during normal resolution' do
		define_resolver('PageInheritedServicesFromSections', from: 'pages', to: 'services') do
			def resolve
				relationships(to: 'sections').each do |section|
					parents(section).each do |parent|
						relationships(parent, to: 'services').each do |service|
							link(service, reference: { 'via' => 'parent' })
						end
					end

					children(section).each do |child|
						relationships(child, to: 'services').each do |service|
							link(service, reference: { 'via' => 'child' })
						end
					end

					descendants(section, min: 2, max: 2).each do |grandchild|
						relationships(grandchild, to: 'services').each do |service|
							link(service, reference: { 'via' => 'grandchild' })
						end
					end
				end
			end
		end

		relationships = {
			'relationships' => [
				{ 'from' => 'sections', 'to' => 'self', 'mode' => 'parent' },
				{ 'from' => 'sections', 'to' => 'services' },
				{ 'from' => 'pages', 'to' => 'sections' },
				{ 'from' => 'pages', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('sections', 'root', {
				'relationships' => {
					'services' => ['services/strategy']
				}
			}),
			collection_document('sections', 'guides', {
				'relationships' => {
					'parent' => 'sections/root'
				}
			}),
			collection_document('sections', 'setup', {
				'relationships' => {
					'parent' => 'sections/guides',
					'services' => ['services/implementation']
				}
			}),
			collection_document('sections', 'api', {
				'relationships' => {
					'parent' => 'sections/setup',
					'services' => ['services/support']
				}
			}),
			collection_document('pages', 'getting-started', {
				'relationships' => {
					'sections' => ['sections/guides']
				}
			}),
			collection_document('services', 'strategy'),
			collection_document('services', 'implementation'),
			collection_document('services', 'support')
		)

		build_relationship_site(collections: %w[sections pages services], relationships: relationships, files: files) do |site, _files|
			page = document_for(site, 'pages', 'getting-started')
			services = page.data.fetch('relationships').fetch('services')

			expect(reference_ids(services)).to eq([
				'services/strategy',
				'services/implementation',
				'services/support'
			])
			expect(reference_values(services, 'via')).to eq(%w[parent child grandchild])
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
