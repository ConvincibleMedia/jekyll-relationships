# frozen_string_literal: true

require 'jekyll-relationships/definitions/normal_relationship'
require 'jekyll-relationships/definitions/tree_relationship'
require 'jekyll-relationships/configuration/defaults'
require 'jekyll-relationships/configuration/debug_setting'
require 'jekyll-relationships/configuration/hash_utilities'
require 'jekyll-relationships/configuration/frontmatter'
require 'jekyll-relationships/configuration/multiple_settings'
require 'jekyll-relationships/configuration/tree_frontmatter'
require 'jekyll-relationships/configuration/tree_settings'
require 'jekyll-relationships/configuration/parser'

module Jekyll
module Plugins

module Relationships

# Normalises the site configuration into explicit relationship definitions.
#
# The object resolves defaults once, exposes the final keyword and frontmatter
# rules, and indexes the concrete relationship definitions used by the engine.
class Configuration
	attr_reader :keywords, :multiple_settings, :reference_template, :tree_settings, :global_frontmatter, :debug

	# Builds the full configuration model from `site.config`.
	def initialize(site_config)
		@string_array = Jekyll::Plugins::Relationships::Support::StringArray.new
		@raw_config = Configuration::HashUtilities.fetch_hash_value(site_config, 'relationships') || {}
		@enabled = build_enabled_setting

		if !enabled?
			initialise_disabled_configuration
			return
		end

		@debug = build_debug_setting
		global_frontmatter_override = Configuration::HashUtilities.fetch_hash_value(@raw_config, 'frontmatter')
		global_tree_override = Configuration::HashUtilities.fetch_hash_value(@raw_config, 'tree')
		@keywords = build_keywords(Configuration::HashUtilities.fetch_hash_value(@raw_config, 'keywords'))
		@multiple_settings = MultipleSettings.new(
			raw_config: Configuration::HashUtilities.fetch_hash_value(@raw_config, 'multiple')
		)
		@global_frontmatter = Frontmatter.new(
			raw_config: Configuration::HashUtilities.merge_hash(
				Defaults::FRONTMATTER,
				global_frontmatter_override
			),
			string_array: @string_array
		)
		@reference_template = References::Template.new(
			config: build_reference_config,
			count_enabled: @multiple_settings.count?
		)
		@tree_settings = TreeSettings.defaults(
			string_array: @string_array
		).merge_level(
			frontmatter_override: global_frontmatter_override,
			tree_override: global_tree_override
		)

		parsed_relationships = Parser.new(
			raw_config: @raw_config,
			string_array: @string_array,
			global_debug: @debug,
			global_frontmatter: @global_frontmatter,
			global_tree_settings: @tree_settings,
			keywords: @keywords
		)

		parsed_result = parsed_relationships.parse
		@normal_relationships = parsed_result.fetch(:normal_relationships)
		@tree_relationships = parsed_result.fetch(:tree_relationships)
		@collections = parsed_result.fetch(:collections)
		attach_resolvers!(parser: parsed_relationships)
	end

	# Returns true when relationship processing is globally enabled.
	def enabled?
		@enabled
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
		@collections.dup
	end

	# Returns every primary-key path used anywhere in the configuration.
	def primary_paths
		normal_paths = @normal_relationships.values.flat_map(&:values).map(&:primary_path)
		tree_paths = @tree_relationships.map(&:primary_path)
		(normal_paths + tree_paths).uniq
	end

	private

	# Builds the active global enabled setting.
	def build_enabled_setting
		return Defaults::ENABLED unless Configuration::HashUtilities.hash_key?(@raw_config, 'enabled')

		Configuration::HashUtilities.boolean_value(
			Configuration::HashUtilities.fetch_hash_value(@raw_config, 'enabled'),
			'relationships.enabled'
		)
	end

	# Sets up the inert configuration used when the plugin is globally disabled.
	def initialise_disabled_configuration
		@debug = Configuration::DebugSetting.disabled
		@keywords = build_keywords(nil)
		@multiple_settings = MultipleSettings.new(raw_config: nil)
		@global_frontmatter = Frontmatter.new(
			raw_config: Defaults::FRONTMATTER,
			string_array: @string_array
		)
		@reference_template = References::Template.new(
			config: default_reference_config,
			count_enabled: @multiple_settings.count?
		)
		@tree_settings = TreeSettings.defaults(string_array: @string_array)
		@normal_relationships = {}
		@tree_relationships = []
		@collections = []
	end

	# Builds the active keyword table.
	def build_keywords(raw_keywords)
		Configuration::HashUtilities.merge_hash(Defaults::KEYWORDS, raw_keywords)
	end

	# Builds the active global debug setting.
	def build_debug_setting
		Configuration::DebugSetting.build(
			value: Configuration::HashUtilities.hash_key?(@raw_config, 'debug') ? Configuration::HashUtilities.fetch_hash_value(@raw_config, 'debug') : Defaults::DEBUG,
			string_array: @string_array,
			context: 'relationships.debug'
		)
	end

	# Builds the resolved reference template config.
	def build_reference_config
		default_references = default_reference_config
		explicit_config = Configuration::HashUtilities.fetch_hash_value(@raw_config, 'references')
		return explicit_config if explicit_config.is_a?(Hash)

		nested_frontmatter = Configuration::HashUtilities.fetch_hash_value(
			Configuration::HashUtilities.fetch_hash_value(@raw_config, 'frontmatter'),
			'references'
		)
		if nested_frontmatter.is_a?(Hash)
			raise ConfigurationError, '`relationships.references` must be configured directly under `relationships`, not under `relationships.frontmatter`.'
		end

		default_references
	end

	# Builds the default reference template shape for the active duplicate mode.
	def default_reference_config
		default_references = {
			'id' => Jekyll::Plugins::Relationships::Support::Placeholders::KEY,
			'collection' => Jekyll::Plugins::Relationships::Support::Placeholders::COLLECTION,
			'page' => Jekyll::Plugins::Relationships::Support::Placeholders::PAGE
		}
		if @multiple_settings.count?
			default_references['count'] = Jekyll::Plugins::Relationships::Support::Placeholders::COUNT
		end

		default_references
	end

	# Attaches registered resolver classes to matching concrete relationships.
	def attach_resolvers!(parser:)
		Resolvers::Base.registered_subclasses.each do |resolver_class|
			parser.pairs_for(
				from_definition: resolver_class.from_definition,
				to_definition: resolver_class.to_definition
			).each do |from_collection, to_collection|
				definition = normal_relationship_for(
					from_collection: from_collection,
					to_collection: to_collection
				)
				next unless definition

				definition.add_resolver(resolver_class)
			end
		end
	end
end

end

end
end
