# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

class Configuration

	# Expands the raw relationship config into explicit definitions.
	#
	# This parser handles shorthand collection lists, target hashes, keyword
	# expansion, duplicate detection, and frontmatter override precedence.
	class Parser
		# Builds one parser for the current configuration.
		def initialize(raw_config:, string_array:, global_debug:, global_frontmatter:, global_tree_settings:, keywords:)
			@raw_config = raw_config
			@string_array = string_array
			@global_debug = global_debug
			@global_frontmatter = global_frontmatter
			@global_tree_settings = global_tree_settings
			@keywords = keywords
		end

		# Parses the full relationship config into concrete definitions.
		def parse
			entries = Configuration::HashUtilities.fetch_hash_value(@raw_config, 'relationships')
			entries = [] if entries.nil?
			raise ConfigurationError, '`relationships.relationships` must be an array.' unless entries.is_a?(Array)

			normal_relationships = Hash.new { |hash, key| hash[key] = {} }
			tree_relationships = []
			collections = Set.new
			occupancy = {}
			sequence = 0

			entries.each_with_index do |entry, entry_index|
				raise ConfigurationError, "Relationship entry #{entry_index + 1} must be a hash." unless entry.is_a?(Hash)

				from_collections = parse_collection_list(
					value: Configuration::HashUtilities.fetch_hash_value(entry, 'from'),
					context: "relationships[#{entry_index}].from"
				)
				raise ConfigurationError, "Relationship entry #{entry_index + 1} must define at least one `from` collection." if from_collections.empty?

				targets = parse_targets(
					value: Configuration::HashUtilities.fetch_hash_value(entry, 'to'),
					context: "relationships[#{entry_index}].to"
				)
				raise ConfigurationError, "Relationship entry #{entry_index + 1} must define at least one `to` target." if targets.empty?

				relationship_frontmatter = Configuration::HashUtilities.fetch_hash_value(entry, 'frontmatter')
				relationship_tree = Configuration::HashUtilities.fetch_hash_value(entry, 'tree')
				relationship_debug = relationship_debug_setting(entry: entry, entry_index: entry_index)
				relationship_mode = normalise_mode(Configuration::HashUtilities.fetch_hash_value(entry, 'mode'))
				effective_relationship_frontmatter = @global_frontmatter.merge(relationship_frontmatter)
				effective_relationship_tree_settings = @global_tree_settings.merge_level(
					frontmatter_override: relationship_frontmatter,
					tree_override: relationship_tree
				)
				effective_relationship_debug = relationship_debug.nil? ? @global_debug : relationship_debug

				from_collections.each do |from_collection|
					collections << from_collection

					targets.each do |target|
						expanded_targets(
							token: target.fetch('collection'),
							from_collections: from_collections,
							current_from_collection: from_collection
						).each do |to_collection|
							collections << to_collection
							effective_mode = normalise_mode(target['mode'].nil? ? relationship_mode : target['mode'])
							effective_frontmatter = effective_relationship_frontmatter.merge(target['frontmatter'])
							effective_tree_settings = effective_relationship_tree_settings.merge_level(
								frontmatter_override: target['frontmatter'],
								tree_override: target['tree']
							)

							if tree_mode?(effective_mode)
								register_tree_relationship(
									tree_relationships: tree_relationships,
									occupancy: occupancy,
									from_collection: from_collection,
									to_collection: to_collection,
									mode: effective_mode,
									frontmatter: effective_frontmatter,
									tree_settings: effective_tree_settings,
									debug: effective_relationship_debug,
									sequence: sequence
								)
								sequence += 1
							else
								sequence = register_normal_relationships(
									normal_relationships: normal_relationships,
									occupancy: occupancy,
									from_collection: from_collection,
									to_collection: to_collection,
									mode: effective_mode,
									frontmatter: effective_frontmatter,
									debug: effective_relationship_debug,
									sequence: sequence
								)
							end
						end
					end
				end
			end

			{
				normal_relationships: normal_relationships,
				tree_relationships: tree_relationships,
				collections: collections.to_a.sort
			}
		end

		# Expands resolver `from` and `to` selectors into explicit pairs.
		def pairs_for(from_definition:, to_definition:)
			from_collections = parse_collection_list(value: from_definition, context: 'resolver.from')

			from_collections.each_with_object([]) do |from_collection, pairs|
				expanded_target_descriptors(to_definition).each do |target|
					expanded_targets(
						token: target.fetch('collection'),
						from_collections: from_collections,
						current_from_collection: from_collection
					).each do |to_collection|
						pairs << [from_collection, to_collection]
					end
				end
			end.uniq
		end

		private

		# Adds one concrete normal relationship pair.
		def register_normal_relationships(normal_relationships:, occupancy:, from_collection:, to_collection:, mode:, frontmatter:, debug:, sequence:)
			ensure_unoccupied_pair!(occupancy, from_collection, to_collection, "normal relationship #{from_collection} -> #{to_collection}")
			normal_relationships[from_collection][to_collection] = build_normal_relationship(
				from_collection: from_collection,
				to_collection: to_collection,
				frontmatter: frontmatter,
				debug: debug,
				sequence: sequence,
				reads_frontmatter: true,
				bidirectional: mode == 'bidirectional'
			)
			occupancy[[from_collection, to_collection]] = mode
			sequence += 1

			return sequence unless mode == 'bidirectional'

			ensure_unoccupied_pair!(occupancy, to_collection, from_collection, "bidirectional reverse relationship #{to_collection} -> #{from_collection}")
			normal_relationships[to_collection][from_collection] = build_normal_relationship(
				from_collection: to_collection,
				to_collection: from_collection,
				frontmatter: frontmatter,
				debug: debug,
				sequence: sequence,
				reads_frontmatter: false,
				bidirectional: true
			)
			occupancy[[to_collection, from_collection]] = mode
			sequence + 1
		end

		# Adds one concrete tree relationship definition.
		def register_tree_relationship(tree_relationships:, occupancy:, from_collection:, to_collection:, mode:, frontmatter:, tree_settings:, debug:, sequence:)
			ensure_unoccupied_pair!(occupancy, from_collection, to_collection, "tree relationship #{from_collection} <-> #{to_collection}")
			ensure_unoccupied_pair!(occupancy, to_collection, from_collection, "tree relationship #{to_collection} <-> #{from_collection}") unless from_collection == to_collection

			tree_relationships << Definitions::TreeRelationship.new(
				from_collection: from_collection,
				to_collection: to_collection,
				primary_path: frontmatter.primary_path,
				parent_child_pairs: parent_child_pairs(from_collection: from_collection, to_collection: to_collection, mode: mode),
				tree_settings: tree_settings,
				debug: debug,
				sequence: sequence
			)

			occupancy[[from_collection, to_collection]] = mode
			occupancy[[to_collection, from_collection]] = mode
		end

		# Builds one normal relationship definition.
		def build_normal_relationship(from_collection:, to_collection:, frontmatter:, debug:, sequence:, reads_frontmatter:, bidirectional:)
			Definitions::NormalRelationship.new(
				from_collection: from_collection,
				to_collection: to_collection,
				primary_path: frontmatter.primary_path,
				foreign_paths: frontmatter.foreign_paths_for(to_collection: to_collection),
				output_path: frontmatter.output_path_for(to_collection: to_collection),
				debug: debug,
				sequence: sequence,
				reads_frontmatter: reads_frontmatter,
				bidirectional: bidirectional
			)
		end

		# Parses one loose collection list into explicit collection labels.
		def parse_collection_list(value:, context:)
			@string_array.interpret(value, split: true, flatten: true).map do |entry|
				string_value = entry.to_s.strip
				raise ConfigurationError, "`#{context}` cannot contain blank collection names." if string_value.empty?

				string_value
			end.uniq
		end

		# Parses one loose target list into explicit target descriptors.
		def parse_targets(value:, context:)
			expanded_target_descriptors(value).each do |target|
				raise ConfigurationError, "`#{context}` target collections cannot be blank." if target.fetch('collection').to_s.strip.empty?
			end
		end

		# Expands strings and hashes into target descriptor hashes.
		def expanded_target_descriptors(value)
			target_entries = value.is_a?(Array) ? value : [value]

			target_entries.flat_map do |target_entry|
				case target_entry
				when String
					@string_array.interpret(target_entry, split: true, flatten: true).map do |collection|
						{ 'collection' => collection.to_s.strip }
					end
				when Hash
					[build_target_descriptor(target_entry)]
				else
					raise ConfigurationError, '`to` entries must be strings or hashes.'
				end
			end
		end

		# Builds one explicit target descriptor while preserving whether optional
		# keys were actually present in the source config.
		def build_target_descriptor(target_entry)
			descriptor = {
				'collection' => Configuration::HashUtilities.fetch_hash_value(target_entry, 'collection').to_s.strip
			}

			%w[frontmatter tree mode].each do |key|
				next unless Configuration::HashUtilities.hash_key?(target_entry, key)

				descriptor[key] = Configuration::HashUtilities.fetch_hash_value(target_entry, key)
			end

			descriptor
		end

		# Expands keyword targets such as `self`, `others`, and `all`.
		def expanded_targets(token:, from_collections:, current_from_collection:)
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

		# Returns true when one mode is a tree mode.
		def tree_mode?(mode)
			%w[parent child parent/child child/parent].include?(mode)
		end

		# Converts one loose mode value into its canonical form.
		def normalise_mode(mode)
			string_mode = mode.nil? ? 'link' : mode.to_s.strip.downcase
			string_mode = 'link' if string_mode.empty?

			return string_mode if %w[link bidirectional parent child parent/child child/parent].include?(string_mode)

			raise ConfigurationError, "Unsupported relationship mode `#{mode}`."
		end

		# Resolves one optional per-relationship debug override.
		def relationship_debug_setting(entry:, entry_index:)
			return nil unless Configuration::HashUtilities.hash_key?(entry, 'debug')

			Configuration::HashUtilities.boolean_value(
				Configuration::HashUtilities.fetch_hash_value(entry, 'debug'),
				"relationships.relationships[#{entry_index}].debug"
			)
		end

		# Builds the allowed parent-child collection directions for one tree mode.
		def parent_child_pairs(from_collection:, to_collection:, mode:)
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

		# Raises when one concrete collection pair has already been defined.
		def ensure_unoccupied_pair!(occupancy, from_collection, to_collection, description)
			return unless occupancy.key?([from_collection, to_collection])

			raise ConfigurationError, "Duplicate or clashing relationship definition for #{description}."
		end

		# Returns one active keyword string.
		def keyword(name)
			@keywords.fetch(name.to_s)
		end
	end
end

end

end
end
