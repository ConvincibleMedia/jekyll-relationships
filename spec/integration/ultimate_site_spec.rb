# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ultimate linked-site scenario' do
	it 'resolves a highly-linked portfolio site with layered resolvers across every normal relationship' do
		define_resolver('UltimateClientOrgTypes', from: 'clients', to: 'org_types') do
			def resolve
				link('orgtype-organisation')
			end
		end

		define_resolver('UltimateClientIndustries', from: 'clients', to: 'industries') do
			def resolve
				relationships.each do |industry|
					ancestors(industry).each do |ancestor|
						link(ancestor, reference: { 'distance' => ancestor.fetch('distance') })
					end
				end
			end
		end

		define_resolver('UltimateClientLocations', from: 'clients', to: 'locations') do
			def resolve
				relationships.each do |location|
					ancestors(location).each do |ancestor|
						link(ancestor, reference: { 'distance' => ancestor.fetch('distance') })
					end
				end
			end
		end

		define_resolver('UltimateOrgTypeServices', from: 'org_types', to: 'services') do
			def resolve
				link('service-account')
			end
		end

		define_resolver('UltimateDeliverableServices', from: 'deliverables', to: 'services') do
			def resolve
				ancestors(min: 1).each do |ancestor|
					relationships(ancestor, to: 'services').each do |service|
						link(service, reference: { 'distance' => ancestor.fetch('distance') })
					end
				end
			end
		end

		define_resolver('UltimateProjectDeliverables', from: 'projects', to: 'deliverables') do
			def resolve
				relationships.each do |deliverable|
					ancestors(deliverable).each do |ancestor|
						link(ancestor, reference: { 'distance' => ancestor.fetch('distance') })
					end
				end
			end
		end

		define_resolver('UltimateProjectClients', from: 'projects', to: 'clients') do
			def resolve
				relationships.dup.each do |client|
					archived = relationships(client, to: 'org_types').any? do |org_type|
						org_type.fetch('id') == 'orgtype-archived'
					end
					unlink(client) if archived
				end
			end
		end

		define_resolver('UltimateProjectServices', from: 'projects', to: 'services') do
			def resolve
				relationships(to: 'deliverables').each do |deliverable|
					relationships(deliverable, to: 'services').each do |service|
						link(service, reference: { 'via' => 'deliverable' })
					end
				end

				relationships(to: 'clients').each do |client|
					relationships(client, to: 'org_types').each do |org_type|
						relationships(org_type, to: 'services').each do |service|
							link(service, reference: { 'via' => 'client' })
						end
					end
				end
			end
		end

		define_resolver('UltimateArticleProjects', from: 'articles', to: 'projects') do
			def resolve
				relationships.dup.each do |project|
					document(project)
					unlink(project) if relationships(project, to: 'clients').empty?
				end
			end
		end

		define_resolver('UltimateArticleClients', from: 'articles', to: 'clients') do
			def resolve
				relationships(to: 'projects').each do |project|
					relationships(project, to: 'clients').each do |client|
						link(client, reference: { 'via' => 'project' })
					end
				end
			end
		end

		define_resolver('UltimateArticleServices', from: 'articles', to: 'services') do
			def resolve
				relationships(to: 'projects').each do |project|
					relationships(project, to: 'services').each do |service|
						link(service, reference: { 'via' => 'project' })
					end
				end
			end
		end

		relationships = {
			'frontmatter' => {
				'base' => 'data',
				'primary' => 'meta.id',
				'foreign' => 'refs.<collection>'
			},
			'tree' => {
				'url' => true
			},
			'relationships' => [
				{ 'from' => 'clients', 'to' => 'org_types, industries, locations' },
				{ 'from' => 'deliverables, industries, locations', 'to' => 'self', 'mode' => 'parent' },
				{ 'from' => 'org_types', 'to' => 'services' },
				{ 'from' => 'deliverables', 'to' => 'services' },
				{
					'from' => 'projects',
					'to' => [
						{
							'collection' => 'services',
							'frontmatter' => {
								'output' => 'resolved.services'
							}
						},
						{
							'collection' => 'deliverables',
							'frontmatter' => {
								'foreign' => 'deliverables, body.details.deliverables'
							}
						},
						{
							'collection' => 'clients',
							'frontmatter' => {
								'foreign' => 'client'
							}
						}
					]
				},
				{
					'from' => 'articles',
					'to' => [
						{
							'collection' => 'projects',
							'frontmatter' => {
								'foreign' => 'related.projects, body.details.projects'
							}
						},
						{
							'collection' => 'clients',
							'frontmatter' => {
								'foreign' => 'related.client',
								'output' => 'resolved.clients'
							}
						},
						{
							'collection' => 'services',
							'frontmatter' => {
								'output' => 'resolved.services'
							}
						}
					]
				}
			]
		}

		files = relationship_site_files(
			collection_documents('services', {
				'discovery' => { 'data' => { 'meta' => { 'id' => 'service-discovery' } } },
				'design' => { 'data' => { 'meta' => { 'id' => 'service-design' } } },
				'compliance' => { 'data' => { 'meta' => { 'id' => 'service-compliance' } } },
				'implementation' => { 'data' => { 'meta' => { 'id' => 'service-implementation' } } },
				'content' => { 'data' => { 'meta' => { 'id' => 'service-content' } } },
				'account' => { 'data' => { 'meta' => { 'id' => 'service-account' } } }
			}),
			collection_documents('org_types', {
				'enterprise' => {
					'data' => {
						'meta' => { 'id' => 'orgtype-enterprise' },
						'refs' => {
							'services' => ['service-implementation']
						}
					}
				},
				'organisation' => {
					'data' => {
						'meta' => { 'id' => 'orgtype-organisation' }
					}
				},
				'archived' => {
					'data' => {
						'meta' => { 'id' => 'orgtype-archived' }
					}
				}
			}),
			collection_documents('industries', {
				'technology' => {
					'data' => {
						'meta' => { 'id' => 'industry-technology' }
					}
				},
				'fintech' => {
					'data' => {
						'meta' => { 'id' => 'industry-fintech' },
						'parent' => 'industry-technology'
					}
				},
				'payments' => {
					'data' => {
						'meta' => { 'id' => 'industry-payments' },
						'parent' => 'industry-fintech'
					}
				},
				'retail' => {
					'data' => {
						'meta' => { 'id' => 'industry-retail' }
					}
				}
			}),
			collection_documents('locations', {
				'uk' => {
					'data' => {
						'meta' => { 'id' => 'location-uk' }
					},
					'permalink' => '/uk/'
				},
				'london' => {
					'data' => {
						'meta' => { 'id' => 'location-london' }
					},
					'permalink' => '/uk/london/'
				}
			}),
			collection_documents('clients', {
				'acme' => {
					'data' => {
						'meta' => { 'id' => 'client-acme' },
						'refs' => {
							'org_types' => ['orgtype-enterprise'],
							'industries' => ['industry-payments'],
							'locations' => ['location-london']
						}
					}
				},
				'legacy' => {
					'data' => {
						'meta' => { 'id' => 'client-legacy' },
						'refs' => {
							'org_types' => ['orgtype-archived'],
							'industries' => ['industry-retail'],
							'locations' => ['location-uk']
						}
					}
				}
			}),
			collection_documents('deliverables', {
				'foundation' => {
					'data' => {
						'meta' => { 'id' => 'deliverable-foundation' },
						'refs' => {
							'services' => ['service-discovery']
						}
					}
				},
				'audit' => {
					'data' => {
						'meta' => { 'id' => 'deliverable-audit' },
						'parent' => 'deliverable-foundation',
						'refs' => {
							'services' => ['service-compliance']
						}
					}
				},
				'launch' => {
					'data' => {
						'meta' => { 'id' => 'deliverable-launch' },
						'parent' => 'deliverable-foundation',
						'refs' => {
							'services' => ['service-design']
						}
					}
				}
			}),
			collection_documents('projects', {
				'phoenix' => {
					'data' => {
						'meta' => { 'id' => 'project-phoenix' },
						'refs' => {
							'services' => ['service-content']
						},
						'deliverables' => ['deliverable-audit'],
						'body' => {
							'details' => {
								'deliverables' => ['deliverable-launch']
							}
						},
						'client' => 'client-acme'
					}
				},
				'legacy' => {
					'data' => {
						'meta' => {
							'id' => 'project-legacy',
							'status' => 'archived'
						},
						'deliverables' => ['deliverable-foundation'],
						'client' => 'client-legacy'
					}
				}
			}),
			collection_documents('articles', {
				'payments-playbook' => {
					'data' => {
						'meta' => { 'id' => 'article-payments-playbook' },
						'refs' => {
							'services' => ['service-content']
						},
						'related' => {
							'projects' => ['project-phoenix'],
							'client' => 'client-acme'
						},
						'body' => {
							'details' => {
								'projects' => ['project-legacy']
							}
						}
					}
				}
			})
		)

		build_relationship_site(
			collections: %w[services org_types industries locations clients deliverables projects articles],
			relationships: relationships,
			files: files
		) do |site, _files|
			client = document_for(site, 'clients', 'acme')
			deliverable = document_for(site, 'deliverables', 'audit')
			project = document_for(site, 'projects', 'phoenix')
			legacy_project = document_for(site, 'projects', 'legacy')
			article = document_for(site, 'articles', 'payments-playbook')

			client_data = client.data.fetch('data').fetch('refs')
			expect(reference_ids(client_data.fetch('org_types'))).to eq(['orgtype-enterprise', 'orgtype-organisation'])
			expect(reference_ids(client_data.fetch('industries'))).to eq([
				'industry-payments',
				'industry-fintech',
				'industry-technology'
			])
			expect(client_data.fetch('industries')[1].fetch('distance')).to eq(1)
			expect(client_data.fetch('industries')[2].fetch('distance')).to eq(2)
			expect(reference_ids(client_data.fetch('locations'))).to eq(['location-london', 'location-uk'])
			expect(client_data.fetch('locations')[1].fetch('distance')).to eq(1)

			deliverable_services = deliverable.data.fetch('data').fetch('refs').fetch('services')
			expect(reference_ids(deliverable_services)).to eq(['service-compliance', 'service-discovery'])
			expect(deliverable_services[1].fetch('distance')).to eq(1)

			project_data = project.data.fetch('data')
			expect(reference_ids(project_data.fetch('deliverables'))).to eq([
				'deliverable-audit',
				'deliverable-launch',
				'deliverable-foundation'
			])
			expect(reference_ids(project_data.fetch('body').fetch('details').fetch('deliverables'))).to eq(['deliverable-launch'])
			expect(reference_ids(project_data.fetch('client'))).to eq(['client-acme'])
			expect(reference_ids(project_data.fetch('resolved').fetch('services'))).to eq([
				'service-content',
				'service-compliance',
				'service-discovery',
				'service-design',
				'service-implementation',
				'service-account'
			])

			expect(legacy_project.data.fetch('data').fetch('client')).to eq([])

			article_data = article.data.fetch('data')
			expect(reference_ids(article_data.fetch('related').fetch('projects'))).to eq(['project-phoenix'])
			expect(reference_ids(article_data.fetch('body').fetch('details').fetch('projects'))).to eq(['project-legacy'])
			expect(reference_ids(article_data.fetch('related').fetch('client'))).to eq(['client-acme'])
			expect(reference_ids(article_data.fetch('resolved').fetch('clients'))).to eq(['client-acme'])
			expect(reference_ids(article_data.fetch('resolved').fetch('services'))).to eq([
				'service-content',
				'service-compliance',
				'service-discovery',
				'service-design',
				'service-implementation',
				'service-account'
			])
		end
	end
end
