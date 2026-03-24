# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

class Configuration

	# Normalises one relationship-level or target-level prune configuration block.
	#
	# Relationship entries and hash-form targets may opt into pruning by defining
	# a minimum neighbour count and, optionally, switching the subject of the rule
	# to the inverse side of the relationship. Tree prune rules may also
	# constrain which depths are eligible for pruning.
	class PruneRuleSettings
		attr_reader :mode, :min, :depth

		# Interprets one loose prune config value.
		def self.build(raw_config:, context:)
			return false if raw_config == false
			return new(raw_config: raw_config, context: context, shortcut: true) if raw_config.is_a?(Integer)

			new(raw_config: raw_config, context: context, shortcut: false)
		end

		# Builds one immutable prune-rule helper from raw configuration.
		def initialize(raw_config:, context:, shortcut:)
			@shortcut = shortcut
			if @shortcut
				@mode = 'direct'
				@min = normalise_min(raw_config, context: context)
				@depth = nil
				return
			end

			raise ConfigurationError, "`#{context}` must be a hash." unless raw_config.is_a?(Hash)

			@mode = normalise_mode(
				Configuration::HashUtilities.hash_key?(raw_config, 'mode') ? Configuration::HashUtilities.fetch_hash_value(raw_config, 'mode') : nil,
				context: context
			)
			@min = normalise_min(
				Configuration::HashUtilities.fetch_hash_value(raw_config, 'min'),
				context: context
			)
			@depth = normalise_depth(
				Configuration::HashUtilities.hash_key?(raw_config, 'depth') ? Configuration::HashUtilities.fetch_hash_value(raw_config, 'depth') : nil,
				context: context
			)
		end

		# Returns true when the rule prunes the inverse side of the relationship.
		def inverse?
			@mode == 'inverse'
		end

		# Returns true when the rule came from the integer shorthand form.
		def shortcut?
			@shortcut
		end

		private

		# Resolves the configured prune mode.
		def normalise_mode(raw_mode, context:)
			return 'direct' if raw_mode.nil?

			string_mode = raw_mode.to_s.strip.downcase
			return 'direct' if string_mode.empty?
			return 'inverse' if string_mode == 'inverse'

			raise ConfigurationError, "Unsupported `#{context}.mode` value `#{raw_mode}`."
		end

		# Resolves the configured minimum count and rejects non-positive values.
		def normalise_min(raw_min, context:)
			raise ConfigurationError, "`#{context}` must define `min`." if raw_min.nil?

			interpreted_min = Configuration::HashUtilities.integer_value(raw_min, "#{context}.min")
			raise ConfigurationError, "`#{context}.min` must be at least 1." if interpreted_min < 1

			interpreted_min
		end

		# Resolves the optional tree depth selector.
		def normalise_depth(raw_depth, context:)
			return nil if raw_depth.nil?

			interpreted_depth = Configuration::HashUtilities.integer_value(raw_depth, "#{context}.depth")
			raise ConfigurationError, "`#{context}.depth` cannot be 0." if interpreted_depth == 0

			interpreted_depth
		end
	end
end

end

end
end
