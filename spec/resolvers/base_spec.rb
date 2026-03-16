# frozen_string_literal: true

RSpec.describe Jekyll::Plugins::Relationships::Resolvers::Base do
	describe '.registered_subclasses' do
		it 'only includes resolvers once both selectors have been declared' do
			resolver_class = Class.new(described_class)

			expect(described_class.registered_subclasses).not_to include(resolver_class)

			resolver_class.from('projects')

			expect(described_class.registered_subclasses).not_to include(resolver_class)

			resolver_class.to('services')

			expect(described_class.registered_subclasses).to include(resolver_class)
		end
	end
end
