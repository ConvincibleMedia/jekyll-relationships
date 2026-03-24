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
		def initialize(raw_config:, string_array:, global_debug:, global_frontmatter:, global_tree_settings:, keywords:, prune_settings:)
			@raw_config = raw_config
			@string_array = string_array
			@global_debug = global_debug
			@global_frontmatter = global_frontmatter
			@global_tree_settings = global_tree_settings
			@keywords = keywords
			@prune_settings = prune_settings
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
			configured_relationships = []
			normal_prune_rules = []
			tree_prune_rules = []
			prune_rule_occupancy = Hash.new { |hash, key| hash[key] = [] }
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
				relationship_prune_configuration = relationship_prune_setting(entry: entry, entry_index: entry_index)
				relationship_debug = relationship_debug_setting(entry: entry, entry_index: entry_index)
				relationship_mode = normalise_mode(Configuration::HashUtilities.fetch_hash_value(entry, 'mode'))
				effective_relationship_frontmatter = @global_frontmatter.merge(relationship_frontmatter)
				effective_relationship_tree_settings = @global_tree_settings.merge_level(
					frontmatter_override: relationship_frontmatter,
					tree_override: relationship_tree
				)
				effective_relationship_debug = relationship_debug.nil? ? @global_debug : relationship_debug
				prune_members_by_configuration = Hash.new { |hash, key| hash[key] = [] }
				target_prune_configuration_cache = {}
				resolved_targets = targets.map do |target|
					{
						descriptor: target,
						prune_overridden: target.key?('prune'),
						prune_configuration: target_prune_setting(target: target, entry_index: entry_index, cache: target_prune_configuration_cache),
						debug_setting: target_debug_setting(target: target, entry_index: entry_index)
					}
				end

				from_collections.each do |from_collection|
					collections << from_collection

					resolved_targets.each do |resolved_target|
						target = resolved_target.fetch(:descriptor)
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
							target_debug = resolved_target.fetch(:debug_setting)
							effective_debug = target_debug.nil? ? effective_relationship_debug : target_debug
							effective_prune_configuration = effective_prune_configuration(
								target_prune_configuration: resolved_target.fetch(:prune_configuration),
								target_overrides_prune: resolved_target.fetch(:prune_overridden),
								relationship_prune_configuration: relationship_prune_configuration
							)

							if tree_mode?(effective_mode)
								tree_definition = register_tree_relationship(
									tree_relationships: tree_relationships,
									occupancy: occupancy,
									from_collection: from_collection,
									to_collection: to_collection,
									mode: effective_mode,
									frontmatter: effective_frontmatter,
									tree_settings: effective_tree_settings,
									debug: effective_debug,
									sequence: sequence
								)
								configured_relationships << build_configured_relationship(
									definition: tree_definition,
									kind: :tree,
									mode: effective_mode,
									sequence: sequence
								)
								register_prune_member!(
									prune_members_by_configuration: prune_members_by_configuration,
									prune_configuration: effective_prune_configuration,
									member: configured_relationships.last
								)
								sequence += 1
							else
								registration = register_normal_relationships(
									normal_relationships: normal_relationships,
									occupancy: occupancy,
									from_collection: from_collection,
									to_collection: to_collection,
									mode: effective_mode,
									frontmatter: effective_frontmatter,
									debug: effective_debug,
									sequence: sequence
								)
								configured_relationships << build_configured_relationship(
									definition: registration.fetch(:definition),
									kind: :normal,
									mode: effective_mode,
									sequence: sequence
								)
								register_prune_member!(
									prune_members_by_configuration: prune_members_by_configuration,
									prune_configuration: effective_prune_configuration,
									member: configured_relationships.last
								)
								sequence = registration.fetch(:sequence)
							end
						end
					end
				end

				prune_members_by_configuration.each do |prune_configuration, prune_members|
					register_prune_rules!(
						entry_members: prune_members,
						prune_configuration: prune_configuration,
						normal_prune_rules: normal_prune_rules,
						tree_prune_rules: tree_prune_rules,
						prune_rule_occupancy: prune_rule_occupancy,
						entry_index: entry_index
					)
				end
			end

			{
				normal_relationships: normal_relationships,
				tree_relationships: tree_relationships,
				collections: collections.to_a.sort,
				configured_relationships: configured_relationships,
				normal_prune_rules: normal_prune_rules,
				tree_prune_rules: tree_prune_rules
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
			forward_definition = build_normal_relationship(
				from_collection: from_collection,
				to_collection: to_collection,
				frontmatter: frontmatter,
				debug: debug,
				sequence: sequence,
				reads_frontmatter: true,
				bidirectional: mode == 'bidirectional'
			)
			normal_relationships[from_collection][to_collection] = forward_definition
			occupancy[[from_collection, to_collection]] = mode
			sequence += 1

			return {
				sequence: sequence,
				definition: forward_definition
			} unless mode == 'bidirectional'

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
			{
				sequence: sequence + 1,
				definition: forward_definition
			}
		end

		# Adds one concrete tree relationship definition.
		def register_tree_relationship(tree_relationships:, occupancy:, from_collection:, to_collection:, mode:, frontmatter:, tree_settings:, debug:, sequence:)
			ensure_unoccupied_pair!(occupancy, from_collection, to_collection, "tree relationship #{from_collection} <-> #{to_collection}")
			ensure_unoccupied_pair!(occupancy, to_collection, from_collection, "tree relationship #{to_collection} <-> #{from_collection}") unless from_collection == to_collection

			definition = Definitions::TreeRelationship.new(
				from_collection: from_collection,
				to_collection: to_collection,
				primary_path: frontmatter.primary_path,
				parent_child_pairs: parent_child_pairs(from_collection: from_collection, to_collection: to_collection, mode: mode),
				tree_settings: tree_settings,
				debug: debug,
				sequence: sequence
			)
			tree_relationships << definition

			occupancy[[from_collection, to_collection]] = mode
			occupancy[[to_collection, from_collection]] = mode
			definition
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

		# Builds one forward-facing configured relationship member.
		def build_configured_relationship(definition:, kind:, mode:, sequence:)
			Definitions::ConfiguredRelationship.new(
				definition: definition,
				kind: kind,
				mode: mode,
				sequence: sequence
			)
		end

		# Registers every prune rule produced by one raw relationship entry.
		def register_prune_rules!(entry_members:, prune_configuration:, normal_prune_rules:, tree_prune_rules:, prune_rule_occupancy:, entry_index:)
			return unless prune_configuration
			raise ConfigurationError, "Relationship entry #{entry_index + 1} defines `prune` but did not expand to any relationships." if entry_members.empty?

			member_kinds = entry_members.map(&:kind).uniq
			if member_kinds.length > 1
				raise ConfigurationError, "Relationship entry #{entry_index + 1} cannot combine tree and normal relationships within one `prune` block."
			end
			if member_kinds.first == :tree
				if prune_configuration.shortcut?
					raise ConfigurationError, "Relationship entry #{entry_index + 1} cannot use `prune: <int>` on a tree relationship."
				end
				if prune_configuration.depth.nil?
					raise ConfigurationError, "Relationship entry #{entry_index + 1} must define `prune.depth` when pruning a tree relationship."
				end
			elsif !prune_configuration.depth.nil?
				raise ConfigurationError, "Relationship entry #{entry_index + 1} cannot define `prune.depth` on a normal relationship."
			end

			prune_rules_for_entry(
				entry_members: entry_members,
				prune_configuration: prune_configuration,
				entry_index: entry_index
			).each do |rule|
				ensure_unoccupied_prune_rule!(prune_rule_occupancy, rule)
				if rule.normal?
					normal_prune_rules << rule
				else
					tree_prune_rules << rule
				end
			end
		end

		# Adds one configured member to the prune group that should govern it.
		def register_prune_member!(prune_members_by_configuration:, prune_configuration:, member:)
			return unless prune_configuration

			prune_members_by_configuration[prune_configuration] << member
		end

		# Expands one raw relationship entry into one or more prune rules.
		def prune_rules_for_entry(entry_members:, prune_configuration:, entry_index:)
			return expanded_prune_rules_for_entry(entry_members: entry_members, prune_configuration: prune_configuration, entry_index: entry_index) unless @prune_settings.combine?

			grouped_members = if prune_configuration.inverse?
									 entry_members.group_by(&:to_collection)
								 else
									 entry_members.group_by(&:from_collection)
								 end
			grouped_members.map do |subject_collection, members|
				build_prune_rule(
					subject_collection: subject_collection,
					members: members,
					prune_configuration: prune_configuration,
					entry_index: entry_index
				)
			end
		end

		# Expands one raw relationship entry into one separate prune rule per member.
		def expanded_prune_rules_for_entry(entry_members:, prune_configuration:, entry_index:)
			entry_members.map do |member|
				build_prune_rule(
					subject_collection: prune_configuration.inverse? ? member.to_collection : member.from_collection,
					members: [member],
					prune_configuration: prune_configuration,
					entry_index: entry_index
				)
			end
		end

		# Builds one concrete prune rule for one subject collection.
		def build_prune_rule(subject_collection:, members:, prune_configuration:, entry_index:)
			Definitions::PruneRule.new(
				kind: members.first.kind,
				subject_collection: subject_collection,
				members: members,
				min: prune_configuration.min,
				depth: prune_configuration.depth,
				inverse: prune_configuration.inverse?,
				entry_index: entry_index
			)
		end

		# Raises when two prune rules overlap on the same subject collection.
		def ensure_unoccupied_prune_rule!(prune_rule_occupancy, rule)
			occupancy_key = [rule.kind, rule.subject_collection]
			existing_rules = prune_rule_occupancy[occupancy_key]
			overlapping_rule = existing_rules.find do |existing_rule|
				!(existing_rule.member_identifiers & rule.member_identifiers).empty?
			end
			if overlapping_rule
				raise ConfigurationError, "Clashing prune rules target collection `#{rule.subject_collection}` more than once across overlapping #{rule.kind} relationships."
			end

			existing_rules << rule
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
					build_target_descriptors(target_entry)
				else
					raise ConfigurationError, '`to` entries must be strings or hashes.'
				end
			end
		end

		# Builds one or more explicit target descriptors while preserving whether
		# optional keys were actually present in the source config.
		def build_target_descriptors(target_entry)
			parse_collection_list(
				value: Configuration::HashUtilities.fetch_hash_value(target_entry, 'collection'),
				context: 'to.collection'
			).map do |collection|
				descriptor = {
					'collection' => collection.to_s.strip
				}

				%w[frontmatter tree mode debug prune].each do |key|
					next unless Configuration::HashUtilities.hash_key?(target_entry, key)

					descriptor[key] = Configuration::HashUtilities.fetch_hash_value(target_entry, key)
				end

				descriptor
			end
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

		# Resolves one optional per-relationship prune block.
		def relationship_prune_setting(entry:, entry_index:)
			return nil unless Configuration::HashUtilities.hash_key?(entry, 'prune')

			Configuration::PruneRuleSettings.build(
				raw_config: Configuration::HashUtilities.fetch_hash_value(entry, 'prune'),
				context: "relationships.relationships[#{entry_index}].prune"
			)
		end

		# Resolves one optional per-relationship debug override.
		def relationship_debug_setting(entry:, entry_index:)
			return nil unless Configuration::HashUtilities.hash_key?(entry, 'debug')

			Configuration::DebugSetting.build(
				value: Configuration::HashUtilities.fetch_hash_value(entry, 'debug'),
				string_array: @string_array,
				context: "relationships.relationships[#{entry_index}].debug"
			)
		end

		# Resolves one optional per-target debug override.
		def target_debug_setting(target:, entry_index:)
			return nil unless target.key?('debug')

			Configuration::DebugSetting.build(
				value: target.fetch('debug'),
				string_array: @string_array,
				context: "relationships.relationships[#{entry_index}].to.debug"
			)
		end

		# Resolves one optional per-target prune override.
		def target_prune_setting(target:, entry_index:, cache:)
			return nil unless target.key?('prune')

			raw_config = target.fetch('prune')
			return cache[raw_config.object_id] if cache.key?(raw_config.object_id)

			cache[raw_config.object_id] = Configuration::PruneRuleSettings.build(
				raw_config: raw_config,
				context: "relationships.relationships[#{entry_index}].to.prune"
			)
		end

		# Resolves the effective prune config for one expanded target.
		#
		# Targets may either inherit the relationship-level rule, replace it with a
		# target-level rule, or explicitly disable it with `prune: false`.
		def effective_prune_configuration(target_prune_configuration:, target_overrides_prune:, relationship_prune_configuration:)
			return target_prune_configuration if target_overrides_prune

			relationship_prune_configuration
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
