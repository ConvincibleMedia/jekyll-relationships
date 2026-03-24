# frozen_string_literal: true

require 'rspec'
require 'jekyll_test_harness'
require 'jekyll-relationships'

# Install the Jekyll integration harness so each example can build a real site.
JekyllTestHarness.install!(framework: :rspec)

Dir[File.expand_path('support/**/*.rb', __dir__)].sort.each do |support_file|
	require support_file
end

RSpec.configure do |config|
	config.disable_monkey_patching!
	config.order = :random

	Kernel.srand config.seed
end
