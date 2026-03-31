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

	describe '.persist' do
		it 'falls back to the global resolver default when the class does not define one' do
			Jekyll::Plugins::Relationships::Resolvers.persist(true)
			resolver_class = Class.new(described_class)

			expect(resolver_class.persist).to be(true)
		end

		it 'lets a resolver class override the global resolver default' do
			Jekyll::Plugins::Relationships::Resolvers.persist(true)
			resolver_class = Class.new(described_class)
			resolver_class.persist(false)

			expect(resolver_class.persist).to be(false)
		end
	end
end
