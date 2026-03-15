# frozen_string_literal: true

require 'rspec'
require 'jekyll_test_harness'
require 'jekyll-relationships'

#require_relative 'support/integration_helpers'

# Install the Jekyll integration harness so each example can build a real site.
JekyllTestHarness.install!(framework: :rspec)

RSpec.configure do |config|
	config.disable_monkey_patching!
	config.order = :random
	#config.include IntegrationHelpers

	Kernel.srand config.seed
end
