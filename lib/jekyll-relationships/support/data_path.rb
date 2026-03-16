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

	# Builds one reusable accessor.
	def initialize
		@reader = Jekyll::Plugins::Relationships::Support::FrontmatterPath.new
	end

	# Reads one value from a nested frontmatter hash.
	def read(data, path)
		return nil if blank_path?(path)

		@reader.traverse(data, path)
	end

	# Writes one value to a nested frontmatter hash, creating hashes as needed.
	def write(data, path, value)
		raise ArgumentError, 'Cannot write to a blank frontmatter path.' if blank_path?(path)

		segments = Jekyll::Plugins::Relationships::Support::FrontmatterPath.split_path(path)
		current_hash = data

		segments[0..-2].each do |segment|
			next_hash = Jekyll::Plugins::Relationships::Support::FrontmatterPath.read_hash(current_hash, segment)
			unless next_hash.is_a?(Hash)
				next_hash = {}
				current_hash[segment] = next_hash
			end
			current_hash = next_hash
		end

		current_hash[segments.last] = value
	end

	private

	# Treats nil and empty strings as unset paths.
	def blank_path?(path)
		path.nil? || path.to_s.strip.empty?
	end
end

end
end

end
end
