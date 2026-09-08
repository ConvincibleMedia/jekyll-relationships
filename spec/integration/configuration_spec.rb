# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'relationships configuration' do
	it 'globally disables the plugin when relationships.enabled is false' do
		files = relationship_site_files(
			collection_document('products', 'alpha', {
				'relationships' => {
					'services' => ['services/design']
				}
			}),
			collection_document('services', 'design')
		)

		build_relationship_site(
			collections: %w[products services],
			relationships: {
				'enabled' => false,
				'relationships' => [
					{ 'from' => 'products', 'to' => 'services' }
				]
			},
			files: files
		) do |site, _files|
			product = document_for(site, 'products', 'alpha')

			expect(product.data.fetch('relationships').fetch('services')).to eq(['services/design'])
		end
	end

	it 'skips relationship parsing entirely when relationships.enabled is false' do
		expect do
			Jekyll::Plugins::Relationships::Configuration.new(
				'relationships' => {
					'enabled' => false,
					'relationships' => 'not-an-array'
				}
			)
		end.not_to raise_error
	end

	it 'supports debug area lists with relationship-level and target-level overrides' do
		configuration = Jekyll::Plugins::Relationships::Configuration.new(
			'relationships' => {
				'debug' => 'resolution, upgrading',
				'relationships' => [
					{
						'from' => 'products',
						'debug' => 'mutations',
						'to' => [
							{ 'collection' => 'categories', 'debug' => 'upgrading, resolvers' },
							{ 'collection' => 'services' }
						]
					}
				]
			}
		)

		categories_relationship = configuration.normal_relationship_for(
			from_collection: 'products',
			to_collection: 'categories'
		)
		services_relationship = configuration.normal_relationship_for(
			from_collection: 'products',
			to_collection: 'services'
		)

		expect(configuration.debug.enabled?('resolution')).to eq(true)
		expect(configuration.debug.enabled?('upgrading')).to eq(true)
		expect(configuration.debug.enabled?('mutations')).to eq(false)
		expect(categories_relationship.debug?('upgrading')).to eq(true)
		expect(categories_relationship.debug?('resolvers')).to eq(true)
		expect(categories_relationship.debug?('mutations')).to eq(false)
		expect(services_relationship.debug?('mutations')).to eq(true)
		expect(services_relationship.debug?('upgrading')).to eq(false)
	end

	it 'supports debug hash filters with IDs and nested log settings' do
		configuration = Jekyll::Plugins::Relationships::Configuration.new(
			'relationships' => {
				'debug' => {
					'ids' => 'products/alpha, categories/one',
					'log' => 'resolution, upgrading'
				},
				'relationships' => [
					{
						'from' => 'products',
						'to' => 'categories'
					}
				]
			}
		)

		expect(configuration.debug.enabled?('resolution')).to eq(true)
		expect(configuration.debug.enabled?('upgrading')).to eq(true)
		expect(configuration.debug.enabled?('mutations')).to eq(false)
		expect(configuration.debug.matches_ids?(['products/alpha'])).to eq(true)
		expect(configuration.debug.matches_ids?(['categories/one'])).to eq(true)
		expect(configuration.debug.matches_ids?(['products/beta'])).to eq(false)
	end

	it 'supports overridden keywords for self relationships while collection placeholders stay literal' do
		relationships = {
			'keywords' => {
				'self' => 'itself'
			},
			'frontmatter' => {
				'base' => 'links',
				'foreign' => '<collection>'
			},
			'relationships' => [
				{ 'from' => 'products', 'to' => 'itself' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'alpha', {
				'links' => {
					'products' => ['products/beta']
				}
			}),
			collection_document('products', 'beta')
		)

		build_relationship_site(collections: %w[products], relationships: relationships, files: files) do |site, _files|
			product = document_for(site, 'products', 'alpha')
			expect(reference_ids(product.data.fetch('links').fetch('products'))).to eq(['products/beta'])
		end
	end

	it 'expands the others keyword across all other source collections' do
		relationships = {
			'frontmatter' => {
				'base' => 'data',
				'foreign' => 'links'
			},
			'relationships' => [
				{ 'from' => 'products, categories', 'to' => 'others' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'alpha', {
				'data' => {
					'links' => ['categories/one']
				}
			}),
			collection_document('categories', 'one', {
				'data' => {
					'links' => ['products/alpha']
				}
			})
		)

		build_relationship_site(collections: %w[products categories], relationships: relationships, files: files) do |site, _files|
			product = document_for(site, 'products', 'alpha')
			category = document_for(site, 'categories', 'one')

			expect(reference_ids(product.data.fetch('data').fetch('links'))).to eq(['categories/one'])
			expect(reference_ids(category.data.fetch('data').fetch('links'))).to eq(['products/alpha'])
		end
	end

	it 'expands the all keyword to include both self and the other collections' do
		relationships = {
			'frontmatter' => {
				'base' => 'data',
				'foreign' => 'refs.<collection>'
			},
			'relationships' => [
				{ 'from' => 'products, categories', 'to' => 'all' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'alpha', {
				'data' => {
					'refs' => {
						'products' => ['products/beta'],
						'categories' => ['categories/one']
					}
				}
			}),
			collection_document('products', 'beta'),
			collection_document('categories', 'one')
		)

		build_relationship_site(collections: %w[products categories], relationships: relationships, files: files) do |site, _files|
			product = document_for(site, 'products', 'alpha')

			expect(reference_ids(product.data.fetch('data').fetch('refs').fetch('products'))).to eq(['products/beta'])
			expect(reference_ids(product.data.fetch('data').fetch('refs').fetch('categories'))).to eq(['categories/one'])
		end
	end

	it 'applies relationship-level and target-level frontmatter overrides in precedence order' do
		relationships = {
			'frontmatter' => {
				'base' => 'data',
				'foreign' => 'refs.<collection>'
			},
			'relationships' => [
				{
					'from' => 'projects',
					'to' => [
						'services',
						{
							'collection' => 'deliverables',
							'frontmatter' => {
								'foreign' => 'custom.deliverables'
							}
						}
					],
					'frontmatter' => {
						'base' => 'meta'
					}
				}
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'meta' => {
					'refs' => {
						'services' => ['services/design']
					},
					'custom' => {
						'deliverables' => ['deliverables/site-map']
					}
				}
			}),
			collection_document('services', 'design'),
			collection_document('deliverables', 'site-map')
		)

		build_relationship_site(collections: %w[projects services deliverables], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')

			expect(reference_ids(project.data.fetch('meta').fetch('refs').fetch('services'))).to eq(['services/design'])
			expect(reference_ids(project.data.fetch('meta').fetch('custom').fetch('deliverables'))).to eq(['deliverables/site-map'])
		end
	end

	it 'supports custom reference template property names' do
		relationships = {
			'multiple' => 'count',
			'references' => {
				'slug' => '<key>',
				'bucket' => '<collection>',
				'entry' => '<page>',
				'occurrences' => '<count>'
			},
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
			collection_document('services', 'design')
		)

		build_relationship_site(collections: %w[projects services], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			reference = project.data.fetch('relationships').fetch('services').first

			expect(reference.keys).to contain_exactly('slug', 'bucket', 'entry', 'occurrences')
			expect(reference.fetch('slug')).to eq('services/design')
			expect(reference.fetch('bucket')).to eq('services')
			expect(reference.fetch('entry')).to be_a(Jekyll::Document)
			expect(reference.fetch('occurrences')).to eq(1)
		end
	end

	it 'builds combined direct prune rules by subject collection by default' do
		configuration = Jekyll::Plugins::Relationships::Configuration.new(
			'relationships' => {
				'relationships' => [
					{
						'from' => 'products, services',
						'to' => 'categories, tags',
						'prune' => {
							'min' => 2
						}
					}
				]
			}
		)

		expect(
			configuration.normal_prune_rules.map do |rule|
				[
					rule.subject_collection,
					rule.members.map(&:to_collection),
					rule.min,
					rule.inverse?
				]
			end
		).to eq([
			['products', %w[categories tags], 2, false],
			['services', %w[categories tags], 2, false]
		])
	end

	it 'builds combined inverse prune rules by target collection' do
		configuration = Jekyll::Plugins::Relationships::Configuration.new(
			'relationships' => {
				'relationships' => [
					{
						'from' => 'projects, products',
						'to' => 'categories, tags',
						'prune' => {
							'mode' => 'inverse',
							'min' => 1
						}
					}
				]
			}
		)

		expect(
			configuration.normal_prune_rules.map do |rule|
				[
					rule.subject_collection,
					rule.members.map(&:from_collection),
					rule.min,
					rule.inverse?
				]
			end
		).to eq([
			['categories', %w[projects products], 1, true],
			['tags', %w[projects products], 1, true]
		])
	end

	it 'treats expanded prune members as separate rules when combine is false' do
		configuration = Jekyll::Plugins::Relationships::Configuration.new(
			'relationships' => {
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
		)

		expect(
			configuration.normal_prune_rules.map do |rule|
				[
					rule.subject_collection,
					rule.members.first.to_collection,
					rule.min
				]
			end
		).to eq([
			['products', 'categories', 1],
			['products', 'services', 1]
		])
	end

	it 'treats prune false as an explicit disable' do
		configuration = Jekyll::Plugins::Relationships::Configuration.new(
			'relationships' => {
				'relationships' => [
					{
						'from' => 'products',
						'to' => 'categories',
						'prune' => false
					}
				]
			}
		)

		expect(configuration.normal_prune_rules).to eq([])
	end

	it 'supports integer prune shorthand on normal relationships' do
		configuration = Jekyll::Plugins::Relationships::Configuration.new(
			'relationships' => {
				'relationships' => [
					{
						'from' => 'products',
						'to' => 'categories',
						'prune' => 2
					}
				]
			}
		)

		rule = configuration.normal_prune_rules.fetch(0)
		expect(rule.subject_collection).to eq('products')
		expect(rule.members.map(&:to_collection)).to eq(['categories'])
		expect(rule.min).to eq(2)
		expect(rule.depth).to be_nil
		expect(rule.inverse?).to eq(false)
	end

	it 'rejects prune blocks that mix tree and normal relationships within one entry' do
		expect do
			Jekyll::Plugins::Relationships::Configuration.new(
				'relationships' => {
					'relationships' => [
						{
							'from' => 'pages',
							'to' => [
								'services',
								{ 'collection' => 'sections', 'mode' => 'parent' }
							],
							'prune' => {
								'min' => 1
							}
						}
					]
				}
			)
		end.to raise_error(Jekyll::Plugins::Relationships::ConfigurationError, /cannot combine tree and normal relationships/i)
	end

	it 'rejects prune blocks with unsupported modes' do
		expect do
			Jekyll::Plugins::Relationships::Configuration.new(
				'relationships' => {
					'relationships' => [
						{
							'from' => 'products',
							'to' => 'categories',
							'prune' => {
								'mode' => 'sideways',
								'min' => 1
							}
						}
					]
				}
			)
		end.to raise_error(Jekyll::Plugins::Relationships::ConfigurationError, /Unsupported `relationships.relationships\[0\].prune.mode` value/i)
	end

	it 'requires depth when pruning a tree relationship' do
		expect do
			Jekyll::Plugins::Relationships::Configuration.new(
				'relationships' => {
					'relationships' => [
						{
							'from' => 'categories',
							'to' => 'self',
							'mode' => 'parent',
							'prune' => {
								'min' => 1
							}
						}
					]
				}
			)
		end.to raise_error(Jekyll::Plugins::Relationships::ConfigurationError, /must define `prune.depth` when pruning a tree relationship/i)
	end

	it 'stores a normalised where-only tree prune rule' do
		configuration = Jekyll::Plugins::Relationships::Configuration.new(
			'relationships' => {
				'relationships' => [
					{
						'from' => 'categories',
						'to' => 'self',
						'mode' => 'parent',
						'prune' => {
							'mode' => 'inverse',
							'where' => {
								' meta.status ' => 'hidden',
								'meta.reason' => nil
							}
						}
					}
				]
			}
		)

		rule = configuration.tree_prune_rules.fetch(0)
		expect(rule.subject_collection).to eq('categories')
		expect(rule.where).to eq({
			'meta.status' => 'hidden',
			'meta.reason' => nil
		})
		expect(rule.min).to be_nil
		expect(rule.depth).to be_nil
		expect(rule.inverse?).to eq(true)
	end

	it 'stores combined relationship and where tree prune modes' do
		configuration = Jekyll::Plugins::Relationships::Configuration.new(
			'relationships' => {
				'relationships' => [
					{
						'from' => 'categories',
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
		)

		rule = configuration.tree_prune_rules.fetch(0)
		expect(rule.min).to eq(2)
		expect(rule.depth).to eq(-1)
		expect(rule.where).to eq('hidden' => true)
	end

	it 'rejects empty and malformed tree prune where hashes' do
		[
			{},
			{ '' => 'hidden' },
			{ ' ' => 'hidden' },
			{ '.meta' => 'hidden' },
			{ 'meta.' => 'hidden' },
			{ 'meta..status' => 'hidden' }
		].each do |where|
			expect do
				Jekyll::Plugins::Relationships::Configuration.new(
					'relationships' => {
						'relationships' => [
							{
								'from' => 'categories',
								'to' => 'self',
								'mode' => 'parent',
								'prune' => {
									'where' => where
								}
							}
						]
					}
				)
			end.to raise_error(Jekyll::Plugins::Relationships::ConfigurationError, /prune\.where/i)
		end
	end

	it 'rejects non-hash tree prune where values' do
		[nil, false, 'hidden', []].each do |where|
			expect do
				Jekyll::Plugins::Relationships::Configuration.new(
					'relationships' => {
						'relationships' => [
							{
								'from' => 'categories',
								'to' => 'self',
								'mode' => 'parent',
								'prune' => {
									'where' => where
								}
							}
						]
					}
				)
			end.to raise_error(Jekyll::Plugins::Relationships::ConfigurationError, /prune\.where.*non-empty hash/i)
		end
	end

	it 'rejects duplicate normalised tree prune where paths' do
		expect do
			Jekyll::Plugins::Relationships::Configuration.new(
				'relationships' => {
					'relationships' => [
						{
							'from' => 'categories',
							'to' => 'self',
							'mode' => 'parent',
							'prune' => {
								'where' => {
									' meta.status ' => 'hidden',
									'meta.status' => 'archived'
								}
							}
						}
					]
				}
			)
		end.to raise_error(Jekyll::Plugins::Relationships::ConfigurationError, /defines path `meta.status` more than once/i)
	end

	it 'applies target-level where overrides and disables inherited where rules' do
		configuration = Jekyll::Plugins::Relationships::Configuration.new(
			'relationships' => {
				'relationships' => [
					{
						'from' => 'pages',
						'to' => [
							{ 'collection' => 'sections', 'mode' => 'parent' },
							{
								'collection' => 'categories',
								'mode' => 'parent',
								'prune' => {
									'where' => {
										'archived' => true
									}
								}
							},
							{
								'collection' => 'groups',
								'mode' => 'parent',
								'prune' => false
							}
						],
						'prune' => {
							'where' => {
								'hidden' => true
							}
						}
					}
				]
			}
		)

		expect(
			configuration.tree_prune_rules.map do |rule|
				[
					rule.members.map(&:to_collection),
					rule.where
				]
			end
		).to eq([
			[['sections'], { 'hidden' => true }],
			[['categories'], { 'archived' => true }]
		])
	end

	it 'expands where rules per tree member when combine is false' do
		configuration = Jekyll::Plugins::Relationships::Configuration.new(
			'relationships' => {
				'prune' => {
					'combine' => false
				},
				'relationships' => [
					{
						'from' => 'pages',
						'to' => 'sections, categories',
						'mode' => 'parent',
						'prune' => {
							'where' => {
								'hidden' => true
							}
						}
					}
				]
			}
		)

		expect(
			configuration.tree_prune_rules.map do |rule|
				[
					rule.members.map(&:to_collection),
					rule.where
				]
			end
		).to eq([
			[['sections'], { 'hidden' => true }],
			[['categories'], { 'hidden' => true }]
		])
	end

	it 'rejects a tree prune block without a complete mode' do
		expect do
			Jekyll::Plugins::Relationships::Configuration.new(
				'relationships' => {
					'relationships' => [
						{
							'from' => 'categories',
							'to' => 'self',
							'mode' => 'parent',
							'prune' => {}
						}
					]
				}
			)
		end.to raise_error(Jekyll::Plugins::Relationships::ConfigurationError, /must define either `prune.where` or both `prune.min` and `prune.depth`/i)
	end

	it 'rejects where on normal prune rules' do
		expect do
			Jekyll::Plugins::Relationships::Configuration.new(
				'relationships' => {
					'relationships' => [
						{
							'from' => 'products',
							'to' => 'categories',
							'prune' => {
								'min' => 1,
								'where' => {
									'hidden' => true
								}
							}
						}
					]
				}
			)
		end.to raise_error(Jekyll::Plugins::Relationships::ConfigurationError, /cannot define `prune.where` on a normal relationship/i)
	end

	it 'requires min when a tree prune rule defines depth' do
		expect do
			Jekyll::Plugins::Relationships::Configuration.new(
				'relationships' => {
					'relationships' => [
						{
							'from' => 'categories',
							'to' => 'self',
							'mode' => 'parent',
							'prune' => {
								'depth' => -1
							}
						}
					]
				}
			)
		end.to raise_error(Jekyll::Plugins::Relationships::ConfigurationError, /must define `prune.min` when defining `prune.depth`/i)
	end

	it 'rejects integer prune shorthand on tree relationships' do
		expect do
			Jekyll::Plugins::Relationships::Configuration.new(
				'relationships' => {
					'relationships' => [
						{
							'from' => 'categories',
							'to' => 'self',
							'mode' => 'parent',
							'prune' => 1
						}
					]
				}
			)
		end.to raise_error(Jekyll::Plugins::Relationships::ConfigurationError, /cannot use `prune: <int>` on a tree relationship/i)
	end

	it 'rejects depth on normal prune rules' do
		expect do
			Jekyll::Plugins::Relationships::Configuration.new(
				'relationships' => {
					'relationships' => [
						{
							'from' => 'products',
							'to' => 'categories',
							'prune' => {
								'min' => 1,
								'depth' => 1
							}
						}
					]
				}
			)
		end.to raise_error(Jekyll::Plugins::Relationships::ConfigurationError, /cannot define `prune.depth` on a normal relationship/i)
	end

	it 'rejects prune depth 0' do
		expect do
			Jekyll::Plugins::Relationships::Configuration.new(
				'relationships' => {
					'relationships' => [
						{
							'from' => 'categories',
							'to' => 'self',
							'mode' => 'parent',
							'prune' => {
								'min' => 1,
								'depth' => 0
							}
						}
					]
				}
			)
		end.to raise_error(Jekyll::Plugins::Relationships::ConfigurationError, /`relationships.relationships\[0\].prune.depth` cannot be 0/i)
	end

	it 'stores tree prune depth on parsed rules' do
		configuration = Jekyll::Plugins::Relationships::Configuration.new(
			'relationships' => {
				'relationships' => [
					{
						'from' => 'categories',
						'to' => 'self',
						'mode' => 'parent',
						'prune' => {
							'mode' => 'inverse',
							'min' => 2,
							'depth' => -1
						}
					}
				]
			}
		)

		rule = configuration.tree_prune_rules.first
		expect(rule.depth).to eq(-1)
		expect(rule.inverse?).to eq(true)
		expect(rule.min).to eq(2)
	end

	it 'expands comma-delimited hash-form target collections and applies target-level prune rules' do
		configuration = Jekyll::Plugins::Relationships::Configuration.new(
			'relationships' => {
				'relationships' => [
					{
						'from' => 'projects',
						'to' => [
							{
								'collection' => 'audiences, org_types, industries',
								'prune' => {
									'min' => 1
								}
							},
							{
								'collection' => 'clients',
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
		)

		expect(configuration.normal_relationship_for(from_collection: 'projects', to_collection: 'audiences')).not_to be_nil
		expect(configuration.normal_relationship_for(from_collection: 'projects', to_collection: 'org_types')).not_to be_nil
		expect(configuration.normal_relationship_for(from_collection: 'projects', to_collection: 'industries')).not_to be_nil
		expect(configuration.normal_relationship_for(from_collection: 'projects', to_collection: 'clients')).not_to be_nil

		expect(
			configuration.normal_prune_rules.map do |rule|
				[
					rule.subject_collection,
					rule.members.map(&:to_collection),
					rule.min,
					rule.inverse?
				]
			end
		).to eq([
			['clients', ['clients'], 1, true],
			['projects', %w[audiences org_types industries], 1, false]
		])
	end

	it 'lets target-level prune false disable relationship-level prune for that target only' do
		configuration = Jekyll::Plugins::Relationships::Configuration.new(
			'relationships' => {
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
		)

		expect(
			configuration.normal_prune_rules.map do |rule|
				[
					rule.subject_collection,
					rule.members.map(&:to_collection),
					rule.min,
					rule.inverse?
				]
			end
		).to eq([
			['projects', ['industries'], 1, false]
		])
	end

	it 'lets target-level prune override relationship-level prune for that target only' do
		configuration = Jekyll::Plugins::Relationships::Configuration.new(
			'relationships' => {
				'relationships' => [
					{
						'from' => 'projects',
						'to' => [
							'industries',
							{
								'collection' => 'clients',
								'prune' => {
									'mode' => 'inverse',
									'min' => 2
								}
							}
						],
						'prune' => {
							'min' => 1
						}
					}
				]
			}
		)

		expect(
			configuration.normal_prune_rules.map do |rule|
				[
					rule.subject_collection,
					rule.members.map(&:to_collection),
					rule.min,
					rule.inverse?
				]
			end
		).to eq([
			['clients', ['clients'], 2, true],
			['projects', ['industries'], 1, false]
		])
	end

	it 'clamps prune iterations and normalises orphan mode aliases' do
		configuration = Jekyll::Plugins::Relationships::Configuration.new(
			'relationships' => {
				'prune' => {
					'iterations' => 999,
					'tree' => {
						'orphans' => 'grandparent required'
					}
				},
				'relationships' => []
			}
		)

		expect(configuration.prune_settings.iterations).to eq(100)
		expect(configuration.prune_settings.prune_rounds).to eq(101)
		expect(configuration.prune_settings.tree_orphans).to eq('grandparents required')
	end

	it 'requires an explicit <count> property when custom references are used in count mode' do
		relationships = {
			'multiple' => 'count',
			'references' => {
				'slug' => '<key>',
				'bucket' => '<collection>',
				'entry' => '<page>'
			},
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha'),
			collection_document('services', 'design')
		)

		expect do
			build_relationship_site(collections: %w[projects services], relationships: relationships, files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /<count>/i)
	end

	it 'ignores configured <count> properties outside count mode' do
		relationships = {
			'multiple' => 'drop',
			'references' => {
				'slug' => '<key>',
				'bucket' => '<collection>',
				'entry' => '<page>',
				'occurrences' => '<count>'
			},
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'relationships' => {
					'services' => [
						{ 'slug' => 'services/design', 'occurrences' => 9 },
						{ 'slug' => 'services/design', 'occurrences' => 2 }
					]
				}
			}),
			collection_document('services', 'design')
		)

		build_relationship_site(collections: %w[projects services], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			reference = project.data.fetch('relationships').fetch('services').first

			expect(reference.keys).to contain_exactly('slug', 'bucket', 'entry')
			expect(reference.fetch('slug')).to eq('services/design')
		end
	end

	it 'rejects duplicate sorting outside count mode' do
		relationships = {
			'multiple' => {
				'mode' => 'keep',
				'sort' => 'desc'
			},
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha'),
			collection_document('services', 'design')
		)

		expect do
			build_relationship_site(collections: %w[projects services], relationships: relationships, files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /multiple\.sort/i)
	end

	it 'rejects reference config nested under frontmatter' do
		relationships = {
			'frontmatter' => {
				'references' => {
					'slug' => '<key>'
				}
			},
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha'),
			collection_document('services', 'design')
		)

		expect do
			build_relationship_site(collections: %w[projects services], relationships: relationships, files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /relationships\.references.*frontmatter/i)
	end

	it 'resolves key-only references when primary keys are unique site-wide' do
		relationships = {
			'frontmatter' => {
				'base' => '',
				'primary' => 'id',
				'foreign' => 'links'
			},
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'services, clients' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', {
				'id' => 'project-alpha',
				'links' => ['service-design', 'client-acme']
			}),
			collection_document('services', 'design', { 'id' => 'service-design' }),
			collection_document('clients', 'acme', { 'id' => 'client-acme' })
		)

		build_relationship_site(collections: %w[projects services clients], relationships: relationships, files: files) do |site, _files|
			project = document_for(site, 'projects', 'alpha')
			links = project.data.fetch('links')

			expect(reference_ids(links)).to eq(['service-design', 'client-acme'])
			expect(links.map { |reference| reference.fetch('collection') }).to eq(%w[services clients])
		end
	end

	it 'raises when a key-only reference is ambiguous across the site' do
		relationships = {
			'frontmatter' => {
				'base' => '',
				'primary' => 'id',
				'foreign' => 'links'
			},
			'relationships' => [
				{ 'from' => 'products', 'to' => 'categories, tags' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'alpha', {
				'id' => 'product-alpha',
				'links' => ['shared']
			}),
			collection_document('categories', 'one', { 'id' => 'shared' }),
			collection_document('tags', 'one', { 'id' => 'shared' })
		)

		expect do
			build_relationship_site(collections: %w[products categories tags], relationships: relationships, files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /ambiguous/i)
	end

	it 'raises when relationship config references collections missing from the site' do
		relationships = {
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'clients' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha')
		)

		expect do
			build_relationship_site(collections: %w[projects], relationships: relationships, files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /relationship collections are not defined on the site: clients/i)
	end

	it 'raises when primary keys are duplicated within a collection' do
		relationships = {
			'frontmatter' => {
				'base' => '',
				'primary' => 'id'
			},
			'relationships' => [
				{ 'from' => 'projects', 'to' => 'services' }
			]
		}

		files = relationship_site_files(
			collection_document('projects', 'alpha', { 'id' => 'project-alpha' }),
			collection_document('services', 'design', { 'id' => 'shared' }),
			collection_document('services', 'build', { 'id' => 'shared' })
		)

		expect do
			build_relationship_site(collections: %w[projects services], relationships: relationships, files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /duplicated within collection/i)
	end

	it 'rejects duplicate and clashing relationship definitions' do
		relationships = {
			'relationships' => [
				{ 'from' => 'products', 'to' => 'services', 'mode' => 'bidirectional' },
				{ 'from' => 'services', 'to' => 'products' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'alpha'),
			collection_document('services', 'design')
		)

		expect do
			build_relationship_site(collections: %w[products services], relationships: relationships, files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /duplicate|clashing/i)
	end

	it 'rejects unsupported relationship modes' do
		relationships = {
			'relationships' => [
				{ 'from' => 'products', 'to' => 'services', 'mode' => 'sideways' }
			]
		}

		files = relationship_site_files(
			collection_document('products', 'alpha'),
			collection_document('services', 'design')
		)

		expect do
			build_relationship_site(collections: %w[products services], relationships: relationships, files: files) { |_site, _files| nil }
		end.to raise_error(JekyllTestHarness::SiteBuildError, /unsupported relationship mode/i)
	end
end
