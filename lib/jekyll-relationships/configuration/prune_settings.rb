# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

class Configuration

	# Encapsulates the global settings that control pruning behaviour.
	#
	# These settings determine whether expanded relationship entries should be
	# combined into one prune rule per subject collection, how many prune rounds
	# may run before the final rebuild pass, and how tree orphans should be
	# handled after parent documents disappear.
	class PruneSettings
		DEFAULTS = {
			'combine' => true,
			'iterations' => 10,
			'tree' => {
				'orphans' => 'grandparents'
			}.freeze
		}.freeze

		attr_reader :iterations, :tree_orphans

		# Builds one prune-settings helper from raw configuration.
		def initialize(raw_config:)
			config = normalise_config(raw_config)
			@combine = Configuration::HashUtilities.boolean_value(config.fetch('combine'), 'relationships.prune.combine')
			@iterations = normalise_iterations(config.fetch('iterations'))
			@tree_orphans = normalise_tree_orphans(Configuration::HashUtilities.fetch_hash_value(config, 'tree'))
		end

		# Returns true when expanded relationship members should combine by subject collection.
		def combine?
			@combine
		end

		# Returns the total number of prune rounds to run before the final rebuild pass.
		def prune_rounds
			@iterations + 1
		end

		private

		# Converts the loose raw value into one normalised hash.
		def normalise_config(raw_config)
			return DEFAULTS if raw_config.nil?
			raise ConfigurationError, '`relationships.prune` must be a hash.' unless raw_config.is_a?(Hash)

			Configuration::HashUtilities.merge_hash(DEFAULTS, raw_config)
		end

		# Clamps the configured prune-round iteration count into the supported range.
		def normalise_iterations(raw_iterations)
			interpreted_iterations = Configuration::HashUtilities.integer_value(raw_iterations, 'relationships.prune.iterations')
			return 0 if interpreted_iterations < 0
			return 100 if interpreted_iterations > 100

			interpreted_iterations
		end

		# Resolves the configured orphan-handling mode for tree pruning.
		def normalise_tree_orphans(raw_tree_config)
			tree_config = raw_tree_config.is_a?(Hash) ? raw_tree_config : {}
			raw_mode = Configuration::HashUtilities.hash_key?(tree_config, 'orphans') ? Configuration::HashUtilities.fetch_hash_value(tree_config, 'orphans') : DEFAULTS.fetch('tree').fetch('orphans')
			string_mode = raw_mode.to_s.strip.downcase
			string_mode = DEFAULTS.fetch('tree').fetch('orphans') if string_mode.empty?
			return 'grandparents' if %w[grandparent grandparents].include?(string_mode)
			return 'grandparents required' if %w[grandparent\ required grandparents\ required].include?(string_mode)
			return string_mode if %w[prune orphan].include?(string_mode)

			raise ConfigurationError, "Unsupported relationships.prune.tree.orphans value `#{raw_mode}`."
		end
	end
end

end

end
end
