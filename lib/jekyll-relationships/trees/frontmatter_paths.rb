# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships
module Trees

# Resolves the tree-specific frontmatter paths after the global base is applied.
#
# Tree relationships reuse the normal frontmatter base, so this helper keeps
# every resolved tree path in one place.
class FrontmatterPaths
	# Builds one tree path helper.
	def initialize(global_frontmatter:, tree_settings:)
		@global_frontmatter = global_frontmatter
		@tree_settings = tree_settings
		@resolved_paths = resolve_paths
	end

	# Returns the resolved parent output path.
	def parent
		@resolved_paths.fetch('parent')
	end

	# Returns the resolved child output path.
	def child
		@resolved_paths.fetch('child')
	end

	# Returns the resolved parents output path.
	def parents
		@resolved_paths.fetch('parents')
	end

	# Returns the resolved children output path.
	def children
		@resolved_paths.fetch('children')
	end

	# Returns the resolved ancestors output path.
	def ancestors
		@resolved_paths.fetch('ancestors')
	end

	# Returns the resolved descendants output path.
	def descendants
		@resolved_paths.fetch('descendants')
	end

	# Returns the input paths that should be read for parents.
	def parent_input_paths
		if @tree_settings.max_parents == 1
			[parent]
		else
			[parent, parents].uniq
		end
	end

	# Returns the input paths that should be read for children.
	def child_input_paths
		if @tree_settings.max_children == 1
			[child]
		else
			[child, children].uniq
		end
	end

	private

	# Resolves every tree path against the global frontmatter base.
	def resolve_paths
		@tree_settings.frontmatter.each_with_object({}) do |(name, path), resolved|
			resolved[name] = @global_frontmatter.path_with_base(path)
		end
	end
end

end
end

end
end
