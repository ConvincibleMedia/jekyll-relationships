# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

# Normalises the site configuration into explicit relationship definitions.
#
# The rest of the engine works entirely from this object so it does not need
# to care about defaults, shorthand forms, or README-level sugar.
class Configuration

	DEFAULT_FRONTMATTER = {
		'base' => 'relationships',
		'primary' => nil,
		'foreign' => '<collection>',
		'output' => nil
	}.freeze

	DEFAULT_TREE = {
		'frontmatter' => {
			'parent' => 'parent',
			'child' => 'child',
			'parents' => 'parents',
			'children' => 'children',
			'ancestors' => 'ancestors',
			'descendants' => 'descendants'
		}.freeze,
		'max' => {
			'parents' => -1,
			'children' => -1
		}.freeze,
		'url' => false
	}.freeze

	DEFAULT_KEYWORDS = {
		'self' => 'self',
		'others' => 'others',
		'all' => 'all',
		'collection' => 'collection',
		'key' => 'key',
		'page' => 'page'
	}.freeze

	DEFAULT_REFERENCES = {
		'id' => '<key>',
		'collection' => '<collection>',
		'page' => '<page>'
	}.freeze

	# Represents one fully-expanded normal relationship pair.
	#
	# Each definition is concrete: one source collection and one target
	# collection, with all overrides already applied.
	class NormalRelationshipDefinition
		attr_accessor :mirror_target_collection
		attr_reader :from_collection, :to_collection, :primary_path, :foreign_paths,
			:output_path, :sequence, :reads_frontmatter, :bidirectional, :resolver_classes

		# Captures the final configuration for one concrete pair.
		def initialize(from_collection:, to_collection:, primary_path:, foreign_paths:, output_path:, sequence:, reads_frontmatter:, bidirectional:)
			@from_collection = from_collection
			@to_collection = to_collection
			@primary_path = primary_path
			@foreign_paths = foreign_paths
			@output_path = output_path
			@sequence = sequence
			@reads_frontmatter = reads_frontmatter
			@bidirectional = bidirectional
			@mirror_target_collection = nil
			@resolver_classes = []
		end

		# Returns the canonical write-back path for final resolved links.
		def final_output_path
			@output_path || @foreign_paths.first
		end

		# Registers one resolver class against this pair.
		def add_resolver(resolver_class)
			@resolver_classes << resolver_class
		end
	end

	# Represents one tree relationship between two collections.
	#
	# Tree definitions describe which parent-child directions are valid, plus
	# which primary-key scheme should be used when resolving references.
	class TreeRelationshipDefinition
		attr_reader :from_collection, :to_collection, :primary_path, :sequence

		# Stores the concrete allowed parent-child directions for this pair.
		def initialize(from_collection:, to_collection:, primary_path:, parent_child_pairs:, sequence:)
			@from_collection = from_collection
			@to_collection = to_collection
			@primary_path = primary_path
			@parent_child_pairs = parent_child_pairs
			@sequence = sequence
		end

		# Returns true when the given parent-child collection pair is allowed.
		def allows_parent_child?(parent_collection:, child_collection:)
			@parent_child_pairs.include?([parent_collection, child_collection])
		end

		# Returns every allowed parent-child direction for this definition.
		def parent_child_pairs
			@parent_child_pairs.dup
		end
	end

	attr_reader :keywords, :reference_template, :tree_settings, :global_frontmatter

	# Builds the full configuration model from `site.config`.
	def initialize(site_config)
		@string_array = Jekyll::Plugins::Support::StringArray.new
		@raw_config = fetch_hash_value(site_config, 'relationships') || {}
		@keywords = build_keywords(fetch_hash_value(@raw_config, 'keywords'))
		@global_frontmatter = merge_frontmatter_layers(DEFAULT_FRONTMATTER, fetch_hash_value(@raw_config, 'frontmatter'))
		@reference_template = ReferenceTemplate.new(
			config: build_reference_config,
			keywords: @keywords
		)
		@tree_settings = build_tree_settings(fetch_hash_value(@raw_config, 'tree'))
		@normal_relationships = Hash.new { |hash, key| hash[key] = {} }
		@tree_relationships = []
		@collections = Set.new
		parse_relationships!
		attach_resolvers!
	end

	# Returns the concrete normal relationship definition for one pair.
	def normal_relationship_for(from_collection:, to_collection:)
		collection_relationships = @normal_relationships[from_collection]
		return nil unless collection_relationships

		collection_relationships[to_collection]
	end

	# Returns all normal relationship definitions for one source collection.
	def normal_relationships_for(collection)
		(@normal_relationships[collection] || {}).values.sort_by(&:sequence)
	end

	# Returns all configured tree relationships.
	def tree_relationships
		@tree_relationships.sort_by(&:sequence)
	end

	# Returns every collection that participates in any relationship.
	def collections
		@collections.to_a.sort
	end

	private

	# Reads reference config, allowing the README's nested typo as a fallback.
	def build_reference_config
		default_references = {
			'id' => placeholder('key'),
			'collection' => placeholder('collection'),
			'page' => placeholder('page')
		}
		explicit_config = fetch_hash_value(@raw_config, 'references')
		return merge_hash(default_references, explicit_config) if explicit_config.is_a?(Hash)

		nested_frontmatter = fetch_hash_value(fetch_hash_value(@raw_config, 'frontmatter'), 'references')
		return merge_hash(default_references, nested_frontmatter) if nested_frontmatter.is_a?(Hash)

		default_references
	end

	# Builds the active keyword table.
	def build_keywords(raw_keywords)
		merge_hash(DEFAULT_KEYWORDS, raw_keywords)
	end

	# Builds the global tree settings.
	def build_tree_settings(raw_tree)
		merged_tree = merge_hash(DEFAULT_TREE, raw_tree)
		tree_frontmatter = merge_hash(DEFAULT_TREE.fetch('frontmatter'), fetch_hash_value(merged_tree, 'frontmatter'))
		tree_max = merge_hash(DEFAULT_TREE.fetch('max'), fetch_hash_value(merged_tree, 'max'))

		{
			'frontmatter' => tree_frontmatter,
			'max' => {
				'parents' => integer_value(tree_max['parents'], 'tree.max.parents'),
				'children' => integer_value(tree_max['children'], 'tree.max.children')
			},
			'url' => !!merged_tree['url']
		}
	end

	# Expands raw relationship config into concrete normal and tree definitions.
	def parse_relationships!
		entries = fetch_hash_value(@raw_config, 'relationships')
		entries = [] if entries.nil?
		raise ConfigurationError, '`relationships.relationships` must be an array.' unless entries.is_a?(Array)

		occupancy = {}
		sequence = 0

		entries.each_with_index do |entry, entry_index|
			raise ConfigurationError, "Relationship entry #{entry_index + 1} must be a hash." unless entry.is_a?(Hash)

			from_collections = parse_collection_list(fetch_hash_value(entry, 'from'), "relationships[#{entry_index}].from")
			raise ConfigurationError, "Relationship entry #{entry_index + 1} must define at least one `from` collection." if from_collections.empty?

			targets = parse_targets(fetch_hash_value(entry, 'to'), "relationships[#{entry_index}].to")
			raise ConfigurationError, "Relationship entry #{entry_index + 1} must define at least one `to` target." if targets.empty?

			relationship_frontmatter = fetch_hash_value(entry, 'frontmatter')
			relationship_mode = normalise_mode(fetch_hash_value(entry, 'mode'))

			from_collections.each do |from_collection|
				@collections << from_collection

				targets.each do |target|
					expanded_targets(target.fetch('collection'), from_collections, from_collection).each do |to_collection|
						@collections << to_collection
						effective_mode = normalise_mode(target.fetch('mode', relationship_mode))
						effective_frontmatter = merge_frontmatter_layers(
							@global_frontmatter,
							relationship_frontmatter,
							target['frontmatter']
						)

						if tree_mode?(effective_mode)
							register_tree_relationship(
								occupancy: occupancy,
								from_collection: from_collection,
								to_collection: to_collection,
								mode: effective_mode,
								frontmatter: effective_frontmatter,
								sequence: sequence
							)
							sequence += 1
						else
							sequence = register_normal_relationships(
								occupancy: occupancy,
								from_collection: from_collection,
								to_collection: to_collection,
								mode: effective_mode,
								frontmatter: effective_frontmatter,
								sequence: sequence
							)
						end
					end
				end
			end
		end
	end

	# Adds one normal or bidirectional relationship pair.
	def register_normal_relationships(occupancy:, from_collection:, to_collection:, mode:, frontmatter:, sequence:)
		ensure_unoccupied_pair!(occupancy, from_collection, to_collection, "normal relationship #{from_collection} -> #{to_collection}")
		definition = build_normal_definition(
			from_collection: from_collection,
			to_collection: to_collection,
			frontmatter: frontmatter,
			sequence: sequence,
			reads_frontmatter: true,
			bidirectional: mode == 'bidirectional'
		)
		@normal_relationships[from_collection][to_collection] = definition
		occupancy[[from_collection, to_collection]] = mode
		sequence += 1

		return sequence unless mode == 'bidirectional'

		ensure_unoccupied_pair!(occupancy, to_collection, from_collection, "bidirectional reverse relationship #{to_collection} -> #{from_collection}")
		reverse_definition = build_normal_definition(
			from_collection: to_collection,
			to_collection: from_collection,
			frontmatter: frontmatter,
			sequence: sequence,
			reads_frontmatter: false,
			bidirectional: true
		)
		definition.mirror_target_collection = to_collection
		reverse_definition.mirror_target_collection = from_collection
		@normal_relationships[to_collection][from_collection] = reverse_definition
		occupancy[[to_collection, from_collection]] = mode
		sequence + 1
	end

	# Adds one tree relationship definition and reserves both directions.
	def register_tree_relationship(occupancy:, from_collection:, to_collection:, mode:, frontmatter:, sequence:)
		ensure_unoccupied_pair!(occupancy, from_collection, to_collection, "tree relationship #{from_collection} <-> #{to_collection}")
		ensure_unoccupied_pair!(occupancy, to_collection, from_collection, "tree relationship #{to_collection} <-> #{from_collection}") unless from_collection == to_collection

		@tree_relationships << TreeRelationshipDefinition.new(
			from_collection: from_collection,
			to_collection: to_collection,
			primary_path: resolve_primary_path(frontmatter),
			parent_child_pairs: parent_child_pairs(from_collection, to_collection, mode),
			sequence: sequence
		)

		occupancy[[from_collection, to_collection]] = mode
		occupancy[[to_collection, from_collection]] = mode
	end

	# Builds one concrete normal relationship definition.
	def build_normal_definition(from_collection:, to_collection:, frontmatter:, sequence:, reads_frontmatter:, bidirectional:)
		NormalRelationshipDefinition.new(
			from_collection: from_collection,
			to_collection: to_collection,
			primary_path: resolve_primary_path(frontmatter),
			foreign_paths: resolve_foreign_paths(frontmatter, to_collection),
			output_path: resolve_output_path(frontmatter),
			sequence: sequence,
			reads_frontmatter: reads_frontmatter,
			bidirectional: bidirectional
		)
	end

	# Adds resolver classes to matching concrete normal definitions.
	def attach_resolvers!
		Resolvers::Base.registered_subclasses.each do |resolver_class|
			next if resolver_class == Resolvers::Base
			next if resolver_class.from_definition.nil? || resolver_class.to_definition.nil?

			from_collections = parse_collection_list(resolver_class.from_definition, "#{resolver_class}.from")
			from_collections.each do |from_collection|
				expanded_targets(resolver_class.to_definition, from_collections, from_collection).each do |to_collection|
					definition = normal_relationship_for(from_collection: from_collection, to_collection: to_collection)
					next unless definition

					definition.add_resolver(resolver_class)
				end
			end
		end
	end

	# Converts `from:` strings into explicit collection labels.
	def parse_collection_list(value, context)
		@string_array.interpret(value, split: true, flatten: true).map do |entry|
			string_value = entry.to_s.strip
			raise ConfigurationError, "`#{context}` cannot contain blank collection names." if string_value.empty?

			string_value
		end.uniq
	end

	# Converts `to:` values into target descriptor hashes.
	def parse_targets(value, context)
		target_entries = if value.is_a?(Array)
											 value
										 else
											 [value]
										 end

		target_entries.flat_map do |target_entry|
			case target_entry
			when String
				@string_array.interpret(target_entry, split: true, flatten: true).map { |collection| { 'collection' => collection.to_s.strip } }
			when Hash
				[{
					'collection' => fetch_hash_value(target_entry, 'collection').to_s.strip,
					'frontmatter' => fetch_hash_value(target_entry, 'frontmatter'),
					'mode' => fetch_hash_value(target_entry, 'mode')
				}]
			else
				raise ConfigurationError, "`#{context}` entries must be strings or hashes."
			end
		end
	end

	# Expands keyword targets such as `self`, `others`, and `all`.
	def expanded_targets(token, from_collections, current_from_collection)
		case token
		when keyword('self')
			[current_from_collection]
		when keyword('others')
			from_collections.reject { |collection| collection == current_from_collection }
		when keyword('all')
			from_collections.dup
		else
			[token]
		end.uniq
	end

	# Merges frontmatter override layers while preserving explicit nils.
	def merge_frontmatter_layers(*layers)
		layers.compact.each_with_object({}) do |layer, merged|
			next unless layer.is_a?(Hash)

			layer.each do |key, value|
				merged[key.to_s] = value
			end
		end
	end

	# Returns the active primary-key path for one relationship definition.
	def resolve_primary_path(frontmatter)
		base = resolve_base(frontmatter)
		primary = fetch_hash_value(frontmatter, 'primary')
		return nil if primary.nil?

		apply_base(base, primary.to_s)
	end

	# Returns all foreign input paths for one target collection.
	def resolve_foreign_paths(frontmatter, to_collection)
		foreign = fetch_hash_value(frontmatter, 'foreign')
		paths = @string_array.interpret(foreign, split: true, flatten: true)
		raise ConfigurationError, 'Each normal relationship must define at least one foreign path.' if paths.empty?

		base = resolve_base(frontmatter)
		paths.map do |path|
			string_path = path.to_s.strip
			raise ConfigurationError, 'Foreign paths cannot be blank.' if string_path.empty?

			apply_base(base, string_path.gsub(collection_placeholder, to_collection))
		end.uniq
	end

	# Returns the explicit output path for one relationship, if configured.
	def resolve_output_path(frontmatter)
		output = fetch_hash_value(frontmatter, 'output')
		return nil if output.nil? || output.to_s.strip.empty?

		apply_base(resolve_base(frontmatter), output.to_s)
	end

	# Resolves the active `base` value for one frontmatter block.
	def resolve_base(frontmatter)
		return '' unless frontmatter.is_a?(Hash)

		base = fetch_hash_value(frontmatter, 'base')
		return '' if base.nil?

		base.to_s
	end

	# Prepends one base path when it is present.
	def apply_base(base, path)
		return path if base.to_s.empty?
		return base if path.to_s.empty?

		"#{base}.#{path}"
	end

	# Returns true when the given mode is one of the tree modes.
	def tree_mode?(mode)
		%w[parent child parent/child child/parent].include?(mode)
	end

	# Converts one mode value into its canonical string form.
	def normalise_mode(mode)
		string_mode = mode.nil? ? 'link' : mode.to_s.strip.downcase
		string_mode = 'link' if string_mode.empty?

		return string_mode if %w[link bidirectional parent child parent/child child/parent].include?(string_mode)

		raise ConfigurationError, "Unsupported relationship mode `#{mode}`."
	end

	# Builds the allowed parent-child collection directions for a tree mode.
	def parent_child_pairs(from_collection, to_collection, mode)
		case mode
		when 'parent'
			[[to_collection, from_collection]]
		when 'child'
			[[from_collection, to_collection]]
		when 'parent/child', 'child/parent'
			[[to_collection, from_collection], [from_collection, to_collection]].uniq
		else
			raise ConfigurationError, "Mode `#{mode}` is not a tree mode."
		end
	end

	# Raises when a concrete collection pair has already been defined.
	def ensure_unoccupied_pair!(occupancy, from_collection, to_collection, description)
		return unless occupancy.key?([from_collection, to_collection])

		raise ConfigurationError, "Duplicate or clashing relationship definition for #{description}."
	end

	# Reads one string- or symbol-keyed hash value.
	def fetch_hash_value(hash, key)
		return nil unless hash.is_a?(Hash)

		Jekyll::Plugins::Support::FrontmatterPath.read_hash(hash, key)
	end

	# Deep-merges two hashes without mutating either.
	def merge_hash(base_hash, override_hash)
		base = base_hash.is_a?(Hash) ? base_hash : {}
		override = override_hash.is_a?(Hash) ? override_hash : {}

		base.each_with_object({}) do |(key, value), merged|
			string_key = key.to_s
			override_value = fetch_hash_value(override, string_key)

			merged[string_key] = if value.is_a?(Hash)
													 merge_hash(value, override_value)
												 elsif override.key?(string_key) || override.key?(string_key.to_sym)
													 override_value
												 else
													 value
												 end
		end.tap do |merged|
			override.each do |key, value|
				string_key = key.to_s
				next if merged.key?(string_key)

				merged[string_key] = value
			end
		end
	end

	# Converts one config value to an integer with a helpful error.
	def integer_value(value, context)
		return value if value.is_a?(Integer)
		return value.to_i if value.is_a?(String) && value.strip.match?(/\A-?\d+\z/)

		raise ConfigurationError, "`#{context}` must be an integer."
	end

	# Returns one active keyword string.
	def keyword(name)
		@keywords.fetch(name.to_s)
	end

	# Returns the configured `<collection>` placeholder.
	def collection_placeholder
		"<#{keyword('collection')}>"
	end

	# Returns one placeholder token for the active keyword set.
	def placeholder(name)
		"<#{keyword(name)}>"
	end
end

end

end
end
