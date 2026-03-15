# frozen_string_literal: true

module Jekyll
module Plugins

module Support

# Traverses frontmatter-style nested hashes using configurable path,
# array, and equivalent-key rules.
#
# Use one instance per syntax configuration, then call `with` for scoped
# variations such as template-level separator overrides.
class FrontmatterPath

	DEFAULT_SEPARATOR = '.'
	DEFAULT_ARRAYS = :expand
	UNSET = Object.new.freeze

	attr_reader :separator, :arrays, :equivalent_lookup

	# Splits one configured path into non-blank segments.
	def self.split_path(path, separator = DEFAULT_SEPARATOR)
		path.to_s.split(separator.to_s).map(&:strip).reject(&:empty?)
	end

	# Normalises equivalent-key definitions into a path-aware lookup table.
	#
	# Keys are stored against their full requested path so aliases can be
	# scoped to one nested level only.
	def self.build_equivalent_lookup(raw_equivalents, split_delimiter: StringArray::DEFAULT_DELIMITER)
		return {} if raw_equivalents == false || raw_equivalents.nil?

		string_array = Jekyll::Plugins::Support::StringArray.new(delimiter: split_delimiter)
		lookup = {}
		groups = raw_equivalents.is_a?(Array) ? raw_equivalents : [raw_equivalents]

		groups.each do |group|
			keys = if group.is_a?(Array)
								group.flat_map { |entry| string_array.interpret(entry, split: -1, flatten: true) }
							else
								string_array.interpret(group, split: -1, flatten: true)
							end
			keys = keys.map { |entry| entry.to_s.strip }.reject(&:empty?).uniq
			next if keys.length < 2

			keys.each { |key| lookup[key] = keys }
		end

		lookup
	end

	# Reads a hash entry using exact, string, or symbol lookup.
	def self.read_hash(hash, key)
		return hash[key] if hash.key?(key)

		string_key = key.to_s
		return hash[string_key] if hash.key?(string_key)

		symbol_key = string_key.to_sym
		return hash[symbol_key] if hash.key?(symbol_key)

		nil
	end

	# Resolves the effective key present in one hash for the requested
	# path-so-far.
	def self.resolve_hash_key(hash, requested_key_path, equivalent_lookup, separator: DEFAULT_SEPARATOR)
		string_key_path = requested_key_path.to_s.strip
		return nil if string_key_path.empty?

		group = equivalent_lookup[string_key_path] || [string_key_path]
		candidate_segments = group.map { |candidate_path| split_path(candidate_path, separator).last }.reject(&:empty?).uniq

		candidate_segments.reverse_each do |candidate|
			return candidate if hash.key?(candidate)

			symbol_candidate = candidate.to_sym
			return symbol_candidate if hash.key?(symbol_candidate)
		end

		nil
	end

	# Builds a frontmatter-path helper for one default configuration.
	def initialize(separator: DEFAULT_SEPARATOR, arrays: DEFAULT_ARRAYS, equivalents: nil, equivalent_lookup: UNSET)
		@separator = normalise_separator(separator)
		@arrays = normalise_array_mode(arrays)
		@equivalent_lookup = equivalent_lookup.equal?(UNSET) ? self.class.build_equivalent_lookup(equivalents) : normalise_equivalent_lookup(equivalent_lookup)
	end

	# Builds a clone with selected configuration overrides.
	def with(separator: UNSET, arrays: UNSET, equivalents: UNSET, equivalent_lookup: UNSET)
		resolved_separator = separator.equal?(UNSET) ? @separator : separator
		resolved_arrays = arrays.equal?(UNSET) ? @arrays : arrays

		if !equivalent_lookup.equal?(UNSET)
			return self.class.new(
				separator: resolved_separator,
				arrays: resolved_arrays,
				equivalent_lookup: equivalent_lookup
			)
		end

		if !equivalents.equal?(UNSET)
			return self.class.new(
				separator: resolved_separator,
				arrays: resolved_arrays,
				equivalents: equivalents
			)
		end

		self.class.new(
			separator: resolved_separator,
			arrays: resolved_arrays,
			equivalent_lookup: @equivalent_lookup
		)
	end

	# Traverses one data structure and returns:
	# - `nil` when the path is missing
	# - one raw terminal value when one match is found
	# - an array of raw terminal values when many matches are found
	def traverse(data, path, separator: UNSET, arrays: UNSET, equivalents: UNSET, equivalent_lookup: UNSET)
		active_separator = separator.equal?(UNSET) ? @separator : normalise_separator(separator)
		active_arrays = arrays.equal?(UNSET) ? @arrays : normalise_array_mode(arrays)
		active_lookup = resolve_lookup(equivalents, equivalent_lookup)

		traverse_internal(data, path, separator: active_separator, arrays: active_arrays, equivalent_lookup: active_lookup)
	end

	private

	# Walks the object graph using the effective traversal configuration.
	def traverse_internal(data, path, separator:, arrays:, equivalent_lookup:)
		return nil unless data.is_a?(Hash)

		segments = self.class.split_path(path, separator)
		return nil if segments.empty?

		nodes = [data]
		segments.each_with_index do |_, segment_index|
			next_nodes = []
			requested_key_path = segments.first(segment_index + 1).join(separator.to_s)

			nodes.each do |node|
				if node.is_a?(Array)
					next_nodes.concat(descend_array(node, arrays))
					next
				end
				next unless node.is_a?(Hash)

				resolved_key = self.class.resolve_hash_key(node, requested_key_path, equivalent_lookup, separator: separator)
				next if resolved_key.nil?

				next_nodes << self.class.read_hash(node, resolved_key)
			end

			nodes = if segment_index == segments.length - 1
								next_nodes.compact
							else
								next_nodes.flatten(1).compact
							end
			break if nodes.empty?
		end

		return nil if nodes.empty?
		return nodes.first if nodes.length == 1

		nodes
	end

	# Applies the configured array traversal mode to one intermediate array.
	def descend_array(array, arrays)
		case arrays
		when :first
			array.empty? ? [] : [array.first]
		else
			array
		end
	end

	# Normalises one separator override.
	def normalise_separator(raw_separator)
		separator = raw_separator.to_s
		separator.empty? ? DEFAULT_SEPARATOR : separator
	end

	# Normalises one configured array traversal mode.
	def normalise_array_mode(raw_arrays)
		mode = raw_arrays.to_s.strip.downcase
		mode = DEFAULT_ARRAYS.to_s if mode.empty?

		return :expand if %w[expand all].include?(mode)
		return :first if mode == 'first'

		raise ArgumentError, "Unsupported array traversal mode '#{raw_arrays}'."
	end

	# Accepts only hash lookups for prebuilt equivalent-key data.
	def normalise_equivalent_lookup(raw_lookup)
		raw_lookup.is_a?(Hash) ? raw_lookup : {}
	end

	# Resolves one optional lookup override against the instance default.
	def resolve_lookup(raw_equivalents, raw_equivalent_lookup)
		return normalise_equivalent_lookup(raw_equivalent_lookup) unless raw_equivalent_lookup.equal?(UNSET)
		return self.class.build_equivalent_lookup(raw_equivalents) unless raw_equivalents.equal?(UNSET)

		@equivalent_lookup
	end
end

end

end
end
