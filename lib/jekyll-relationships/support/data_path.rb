# frozen_string_literal: true

module Jekyll
module Plugins
module Relationships

module Support

# Reads and writes dot-separated frontmatter paths on plain nested hashes.
#
# This wrapper keeps all path mutation logic in one place so the rest of the
# engine can stay focused on relationship behaviour rather than hash surgery.
class DataPath
	# Captures one concrete leaf reached by a dotted frontmatter path.
	#
	# Each match remembers the exact container and key so callers can update the
	# original structure surgically without reshaping nearby hashes or arrays.
	class Match
		attr_reader :parent, :key, :value

		# Builds one concrete leaf match.
		def initialize(parent:, key:, value:)
			@parent = parent
			@key = key
			@value = value
		end

		# Replaces the matched leaf in place.
		def write(value)
			@parent[@key] = value
			@value = value
		end
	end

	# Reports the raw value gathered from a path together with its concrete
	# source leaves.
	#
	# `array_traversed?` distinguishes a simple hash path from one that expanded
	# through array items and therefore cannot safely receive one consolidated
	# write-back value.
	class ReadResult
		attr_reader :matches

		# Builds one read result from the collected concrete matches.
		def initialize(matches:, array_traversed:)
			@matches = matches
			@array_traversed = array_traversed
		end

		# Reassembles the public read value from the concrete matches.
		def value
			values = @matches.map(&:value)
			return nil if values.empty?
			return values.first if values.length == 1

			values
		end

		# Returns true when the path resolved to at least one concrete leaf.
		def present?
			!@matches.empty?
		end

		# Returns true when path traversal expanded through an array.
		def array_traversed?
			@array_traversed
		end
	end

	TraversalNode = Struct.new(:parent, :key, :value)

	# Builds one reusable accessor.
	def initialize
		@reader = Jekyll::Plugins::Relationships::Support::FrontmatterPath.new
	end

	# Reads one value together with its concrete leaf matches.
	def read_result(data, path)
		return ReadResult.new(matches: [], array_traversed: false) if blank_path?(path)

		matches, array_traversed = locate_matches(data, path)
		ReadResult.new(matches: matches, array_traversed: array_traversed)
	end

	# Reads one value from a nested frontmatter hash.
	def read(data, path)
		read_result(data, path).value
	end

	# Writes one value to a nested frontmatter hash, creating hashes as needed.
	#
	# Existing non-hash ancestors are treated as errors so write-back never
	# silently replaces arrays or scalar values with new hashes.
	def write(data, path, value)
		raise ArgumentError, 'Cannot write to a blank frontmatter path.' if blank_path?(path)

		segments = Jekyll::Plugins::Relationships::Support::FrontmatterPath.split_path(path)
		current_hash = data

		segments[0..-2].each_with_index do |segment, segment_index|
			next_hash = Jekyll::Plugins::Relationships::Support::FrontmatterPath.read_hash(current_hash, segment)
			if next_hash.nil?
				next_hash = {}
				current_hash[segment] = next_hash
			elsif !next_hash.is_a?(Hash)
				failing_path = segments.first(segment_index + 1).join(@reader.separator.to_s)
				raise ResolutionError, "Cannot write frontmatter path `#{path}` because `#{failing_path}` resolves to a #{next_hash.class}, not a hash."
			end
			current_hash = next_hash
		end

		current_hash[segments.last] = value
	end

	private

	# Finds the concrete leaves currently matched by one path.
	def locate_matches(data, path)
		return [[], false] unless data.is_a?(Hash)

		segments = Jekyll::Plugins::Relationships::Support::FrontmatterPath.split_path(path, @reader.separator)
		return [[], false] if segments.empty?

		nodes = [TraversalNode.new(nil, nil, data)]
		array_traversed = false

		segments.each_with_index do |_, segment_index|
			requested_key_path = segments.first(segment_index + 1).join(@reader.separator.to_s)
			next_nodes = []
			last_segment = segment_index == segments.length - 1

			nodes.each do |node|
				if node.value.is_a?(Array)
					array_traversed = true
					next_nodes.concat(descend_array(node.value))
					next
				end
				next unless node.value.is_a?(Hash)

				resolved_key = Jekyll::Plugins::Relationships::Support::FrontmatterPath.resolve_hash_key(
					node.value,
					requested_key_path,
					@reader.equivalent_lookup,
					separator: @reader.separator
				)
				next if resolved_key.nil?

				child_value = Jekyll::Plugins::Relationships::Support::FrontmatterPath.read_hash(node.value, resolved_key)
				next if child_value.nil?

				if child_value.is_a?(Array) && !last_segment
					array_traversed = true
					next_nodes.concat(descend_array(child_value))
					next
				end

				next_nodes << TraversalNode.new(node.value, resolved_key, child_value)
			end

			nodes = next_nodes
			break if nodes.empty?
		end

		[
			nodes.map { |node| Match.new(parent: node.parent, key: node.key, value: node.value) },
			array_traversed
		]
	end

	# Applies the configured array-expansion rule while keeping exact indices.
	def descend_array(array)
		case @reader.arrays
		when :first
			return [] if array.empty?

			[TraversalNode.new(array, 0, array.first)]
		else
			array.each_with_index.map do |entry, index|
				TraversalNode.new(array, index, entry)
			end
		end
	end

	# Treats nil and empty strings as unset paths.
	def blank_path?(path)
		path.nil? || path.to_s.strip.empty?
	end
end

end

end
end
end
