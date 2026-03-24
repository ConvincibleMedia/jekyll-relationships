# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships
module Generators

# Jekyll generator entry point for relationship processing.
#
# The generator runs early so later generators and renderers can rely on the
# resolved relationship data already being present on documents.
class Relationships < Jekyll::Generator
	safe true
	priority :high

	# Processes the site relationships during the generate phase.
	def generate(site)
		Engine.new(site: site).process!
	end
end

end
end

end
end
