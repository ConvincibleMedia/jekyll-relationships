# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

# Jekyll generator entry point for relationship processing.
#
# The generator runs late enough that collections and plugin-defined resolver
# classes already exist, then mutates document frontmatter before rendering.
class Generator < Jekyll::Generator

	safe true
	priority :lowest

	# Processes the site relationships during the generate phase.
	def generate(site)
		Engine.new(site: site).process!
	end
end

end

end
end
