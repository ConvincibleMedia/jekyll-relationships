# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

class Configuration

	# Normalises the `debug` config into one explicit set of enabled log areas.
	#
	# Supported areas:
	# * `resolution`: relationship-resolution start and finish
	# * `upgrading`: raw reference reading, resolution, and write-back
	# * `mutations`: link and unlink operations
	# * `resolvers`: resolver execution and helper calls
	# * `trees`: tree discovery, edge handling, and tree write-back
	class DebugSetting
		AREAS = {
			'resolution' => 'relationship-resolution lifecycle',
			'upgrading' => 'reference upgrading and write-back',
			'mutations' => 'link and unlink operations',
			'resolvers' => 'resolver execution and helper calls',
			'trees' => 'tree discovery, edge handling, and tree write-back'
		}.freeze

		ALL_AREAS = AREAS.keys.freeze

		class << self
			# Builds one explicit debug setting from a loose config value.
			def build(value:, string_array:, context:)
				return disabled if value.nil? || false_value?(value)
				return all if true_value?(value)

				raw_areas = string_array.interpret(value, split: true, flatten: true)
				raise_invalid_value!(context: context) if raw_areas.empty?

				areas = raw_areas.each_with_object([]) do |raw_area, interpreted_areas|
					normalised_area = normalise_area(raw_area, context: context)
					return all if normalised_area == 'all'

					interpreted_areas << normalised_area
				end

				new(areas.uniq)
			end

			# Returns one disabled debug setting.
			def disabled
				new([])
			end

			# Returns one debug setting that enables every area.
			def all
				new(ALL_AREAS)
			end

			private

			# Returns true when a loose value means "debug everything".
			def true_value?(value)
				value == true || value.to_s.strip.casecmp('true').zero?
			end

			# Returns true when a loose value means "debug nothing".
			def false_value?(value)
				value == false || value.to_s.strip.casecmp('false').zero?
			end

			# Normalises one configured area name and validates it.
			def normalise_area(raw_area, context:)
				area = raw_area.to_s.strip.downcase
				raise_invalid_value!(context: context) if area.empty?
				return 'all' if area == 'all'
				return area if AREAS.key?(area)

				raise ConfigurationError,
					"`#{context}` contains unknown debug area `#{raw_area}`. Supported areas: #{ALL_AREAS.join(', ')}."
			end

			# Raises one shared error for invalid debug values.
			def raise_invalid_value!(context:)
				raise ConfigurationError,
					"`#{context}` must be true, false, `all`, or a comma-delimited string/array of debug areas: #{ALL_AREAS.join(', ')}."
			end
		end

		attr_reader :areas

		# Captures one immutable set of enabled debug areas.
		def initialize(areas)
			@areas = areas.freeze
		end

		# Returns true when any debug area is enabled, or when one named area is enabled.
		def enabled?(area = nil)
			return !@areas.empty? if area.nil?

			@areas.include?(normalise_runtime_area(area))
		end

		private

		# Normalises one runtime area name and raises on internal typos.
		def normalise_runtime_area(area)
			string_area = area.to_s.strip.downcase
			return string_area if self.class::ALL_AREAS.include?(string_area)

			raise ArgumentError, "Unknown runtime debug area `#{area}`."
		end
	end
end

end

end
end
