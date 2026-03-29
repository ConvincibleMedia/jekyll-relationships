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
		HASH_KEYS = %w[ids log].freeze

		ALL_AREAS = AREAS.keys.freeze

		class << self
			# Builds one explicit debug setting from a loose config value.
			def build(value:, string_array:, context:)
				return build_hash_value(value: value, string_array: string_array, context: context) if value.is_a?(Hash)

				build_scalar_value(value: value, string_array: string_array, context: context)
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

			# Builds one debug setting from the legacy scalar forms.
			def build_scalar_value(value:, string_array:, context:)
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

			# Builds one debug setting from the new hash form with optional ID filtering.
			def build_hash_value(value:, string_array:, context:)
				hash_value = stringify_hash(value)
				unknown_keys = hash_value.keys - HASH_KEYS
				unless unknown_keys.empty?
					raise ConfigurationError, "`#{context}` contains unsupported keys #{unknown_keys.sort.join(', ')}. Supported keys: #{HASH_KEYS.join(', ')}."
				end

				log_context = hash_value.key?('log') ? "#{context}.log" : context
				scalar_setting = build_scalar_value(
					value: hash_value.key?('log') ? hash_value.fetch('log') : true,
					string_array: string_array,
					context: log_context
				)
				new(
					scalar_setting.areas,
					parse_ids(
						value: hash_value['ids'],
						string_array: string_array,
						context: "#{context}.ids"
					)
				)
			end

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

			# Parses one optional string-or-array ID filter.
			def parse_ids(value:, string_array:, context:)
				return [] if value.nil?

				raw_ids = string_array.interpret(value, split: true, flatten: true)
				raise ConfigurationError, "`#{context}` must be a string or array of strings." if raw_ids.empty?

				ids = raw_ids.map { |raw_id| raw_id.to_s.strip }.reject(&:empty?).uniq
				raise ConfigurationError, "`#{context}` must contain at least one non-blank ID." if ids.empty?

				ids
			end

			# Converts one config hash to a shallow string-keyed copy.
			def stringify_hash(hash)
				hash.each_with_object({}) do |(key, value), stringified|
					stringified[key.to_s] = value
				end
			end
		end

		attr_reader :areas, :ids

		# Captures one immutable set of enabled debug areas and optional ID filters.
		def initialize(areas, ids = [])
			@areas = areas.freeze
			@ids = Array(ids).map(&:to_s).uniq.freeze
		end

		# Returns true when any debug area is enabled, or when one named area is enabled.
		def enabled?(area = nil)
			return !@areas.empty? if area.nil?

			@areas.include?(normalise_runtime_area(area))
		end

		# Returns true when this setting either has no ID filter or overlaps one.
		def matches_ids?(related_ids)
			return true if @ids.empty?

			Array(related_ids).map(&:to_s).any? { |related_id| @ids.include?(related_id) }
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
