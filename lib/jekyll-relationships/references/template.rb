# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships
module References

# Parses loose reference values and builds canonical relationship hashes.
#
# The template is configured from `relationships.references` and controls which
# property names hold the key, collection, page, and optional count values in
# output hashes.
class Template

	# Represents one parsed reference before or after it is resolved.
	#
	# The `metadata` hash contains any non-reserved properties found on an
	# existing reference hash.
	class ParsedReference
		attr_reader :key, :collection, :page, :count, :metadata, :original_value

		# Captures the parsed reference fields in one immutable object.
		def initialize(key:, collection:, page:, count:, metadata:, original_value:)
			@key = key
			@collection = collection
			@page = page
			@count = count
			@metadata = metadata
			@original_value = original_value
		end

		# Returns true when the parsed reference already points at a document.
		def document?
			@page.is_a?(Jekyll::Document)
		end
	end

	attr_reader :key_property, :collection_property, :page_property, :count_property

	# Builds the reference template from config and duplicate-handling settings.
	def initialize(config:, count_enabled:)
		@config = stringify_hash(config || {})
		@count_enabled = !!count_enabled
		@key_property = nil
		@collection_property = nil
		@page_property = nil
		@count_property = nil

		parse_config!
	end

	# Parses one raw reference value from frontmatter or resolver input.
	def parse(value)
		case value
		when String
			key = value.to_s.strip
			return nil if key.empty?

			ParsedReference.new(
				key: key,
				collection: nil,
				page: nil,
				count: 1,
				metadata: {},
				original_value: value
			)
		when Hash
			parse_hash_reference(value)
		when Jekyll::Document
			ParsedReference.new(
				key: nil,
				collection: nil,
				page: value,
				count: 1,
				metadata: {},
				original_value: value
			)
		else
			raise ConfigurationError, "Unsupported reference value `#{value.inspect}`."
		end
	end

	# Builds one output reference hash for a resolved document.
	def build(document:, key:, metadata: nil, count: 1, include_count: @count_enabled)
		hash = {}
		hash[@key_property] = key
		hash[@collection_property] = document.collection.label if @collection_property
		hash[@page_property] = document if @page_property
		hash[@count_property] = normalise_count(count) if include_count && @count_property

		filter_metadata(metadata).each do |property, value|
			hash[property] = value
		end

		hash
	end

	# Returns the configured property names that are reserved for the engine.
	def reserved_properties
		[@key_property, @collection_property, @page_property, @count_property].compact
	end

	private

	# Validates and captures the configured placeholder mappings.
	def parse_config!
		@config.each do |property, value|
			case value.to_s
			when Jekyll::Plugins::Relationships::Support::Placeholders::KEY
				raise ConfigurationError, 'Reference config can only define one <key> property.' if @key_property
				@key_property = property
			when Jekyll::Plugins::Relationships::Support::Placeholders::COLLECTION
				raise ConfigurationError, 'Reference config can only define one <collection> property.' if @collection_property
				@collection_property = property
			when Jekyll::Plugins::Relationships::Support::Placeholders::PAGE
				raise ConfigurationError, 'Reference config can only define one <page> property.' if @page_property
				@page_property = property
			when Jekyll::Plugins::Relationships::Support::Placeholders::COUNT
				raise ConfigurationError, 'Reference config can only define one <count> property.' if @count_property
				@count_property = property
			else
				raise ConfigurationError, "Unsupported reference template value `#{value.inspect}`. Only placeholder keywords are supported."
			end
		end

		raise ConfigurationError, 'Reference config must define exactly one <key> property.' unless @key_property
		if @count_enabled && @count_property.nil?
			raise ConfigurationError, 'Reference config must define exactly one <count> property when `relationships.multiple` is `count`.'
		end
	end

	# Parses one hash reference according to the configured property names.
	def parse_hash_reference(hash)
		key = fetch_hash_value(hash, @key_property)
		collection = @collection_property ? fetch_hash_value(hash, @collection_property) : nil
		page = @page_property ? fetch_hash_value(hash, @page_property) : nil

		if key.nil? && !page.is_a?(Jekyll::Document)
			raise ResolutionError, "Reference hash `#{hash.inspect}` does not include the configured key property `#{@key_property}`."
		end

		ParsedReference.new(
			key: key,
			collection: collection,
			page: page,
			count: parsed_count(hash),
			metadata: filter_metadata(hash),
			original_value: hash
		)
	end

	# Returns the parsed count value for one reference hash.
	def parsed_count(hash)
		return 1 unless @count_enabled
		return 1 unless @count_property

		raw_count = fetch_hash_value(hash, @count_property)
		return 1 if raw_count.nil?

		normalise_count(raw_count)
	end

	# Removes reserved engine properties from a metadata hash.
	def filter_metadata(hash)
		return {} unless hash.is_a?(Hash)

		metadata = {}
		hash.each do |property, value|
			string_property = property.to_s
			next if reserved_properties.include?(string_property)

			metadata[string_property] = value
		end

		metadata
	end

	# Reads one property from a string- or symbol-keyed hash.
	def fetch_hash_value(hash, property)
		return nil unless property

		Jekyll::Plugins::Relationships::Support::FrontmatterPath.read_hash(hash, property)
	end

	# Converts one hash to a shallow string-keyed copy.
	def stringify_hash(hash)
		return {} unless hash.is_a?(Hash)

		hash.each_with_object({}) do |(key, value), stringified|
			stringified[key.to_s] = value
		end
	end

	# Validates and normalises one reference count.
	def normalise_count(value)
		integer_count = if value.is_a?(Integer)
							 value
						 elsif value.is_a?(String) && value.strip.match?(/\A\d+\z/)
							 value.to_i
						 else
							 raise ResolutionError, "Relationship count `#{value.inspect}` must be a positive integer."
						 end
		raise ResolutionError, "Relationship count `#{value.inspect}` must be a positive integer." if integer_count < 1

		integer_count
	end
end

end
end

end
end
