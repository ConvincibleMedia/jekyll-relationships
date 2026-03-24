lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'jekyll-relationships/version'

Gem::Specification.new do |spec|
	spec.name = 'jekyll-relationships'
	spec.version = Jekyll::Plugins::Relationships::VERSION
	spec.authors = ['Convincible']
	spec.email = ['development@convincible.media']

	spec.summary = "Define and traverse relationships between Jekyll documents."
	spec.description = "Collection documents can specify many-to-many relationships with each other in their frontmatter, forming trees, graphs or relational-database-like structures. Parses the relationships and writes them back to frontmatter."
	spec.homepage = 'https://github.com/ConvincibleMedia/jekyll-relationships'
	spec.license = 'LGPL-3.0-or-later'

	spec.files = Dir['lib/**/*.rb'] + %w[readme.md]
	spec.require_paths = ['lib']

	spec.required_ruby_version = '>= 2.4.4'

	spec.add_dependency 'jekyll', '>= 3.8.5', '< 5.0'

	spec.add_development_dependency 'jekyll-test-harness', '= 0.1.0.alpha'
	spec.add_development_dependency 'pry', '~> 0.13', '>= 0.13.1'
	spec.add_development_dependency 'pry-byebug', '~> 3.9', '>= 3.9.0'
	spec.add_development_dependency 'rspec', '~> 3.10'
end
