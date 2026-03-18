# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

class Configuration

	# Encapsulates the configured handling for duplicate normal relationships.
	#
	# The selected mode determines whether duplicates are counted, dropped, or
	# preserved, while the optional sort controls the final output order in count
	# mode only.
	class MultipleSettings
		attr_reader :mode, :sort

		# Builds one multiple-settings helper from raw configuration.
		def initialize(raw_config:)
			config = normalise_config(raw_config)
			@mode = normalise_mode(config['mode'])
			@sort = normalise_sort(config['sort'])
			validate!
		end

		# Returns true when duplicate links should aggregate into counts.
		def count?
			@mode == 'count'
		end

		# Returns true when duplicate links should be dropped.
		def drop?
			@mode == 'drop'
		end

		# Returns true when duplicate links should be preserved individually.
		def keep?
			@mode == 'keep'
		end

		# Returns true when counted output should be sorted in ascending order.
		def sort_ascending?
			@sort == 'asc'
		end

		# Returns true when counted output should be sorted in descending order.
		def sort_descending?
			@sort == 'desc'
		end

		private

		# Converts the loose raw value into a normalised hash.
		def normalise_config(raw_config)
			case raw_config
			when nil
				Defaults::MULTIPLE
			when String, Symbol
				{ 'mode' => raw_config.to_s }
			when Hash
				Configuration::HashUtilities.merge_hash(Defaults::MULTIPLE, raw_config)
			else
				raise ConfigurationError, '`relationships.multiple` must be a string or hash.'
			end
		end

		# Resolves one configured duplicate-handling mode.
		def normalise_mode(raw_mode)
			string_mode = raw_mode.to_s.strip.downcase
			string_mode = Defaults::MULTIPLE.fetch('mode') if string_mode.empty?

			return string_mode if %w[count drop keep].include?(string_mode)

			raise ConfigurationError, "Unsupported relationships.multiple mode `#{raw_mode}`."
		end

		# Resolves one configured count-sort direction.
		def normalise_sort(raw_sort)
			return nil if raw_sort.nil?

			string_sort = raw_sort.to_s.strip.downcase
			return nil if string_sort.empty?
			return 'asc' if %w[asc ascending].include?(string_sort)
			return 'desc' if %w[desc descending].include?(string_sort)

			raise ConfigurationError, "Unsupported relationships.multiple.sort value `#{raw_sort}`."
		end

		# Raises for mode combinations that are not meaningful.
		def validate!
			return if @sort.nil? || count?

			raise ConfigurationError, '`relationships.multiple.sort` is only supported when `relationships.multiple` is `count`.'
		end
	end
end

end

end
end
