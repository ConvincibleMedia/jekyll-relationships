# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Jekyll::Plugins::Relationships::Support::FrontmatterMatcher do
	def matcher(expected_values)
		described_class.new(expected_values: expected_values)
	end

	it 'matches exact nested scalar, array, and hash terminal values' do
		frontmatter = {
			'meta' => {
				'status' => 'hidden',
				'tags' => %w[legal private],
				'options' => {
					'listed' => false
				}
			}
		}

		expect(
			matcher(
				'meta.status' => 'hidden',
				'meta.tags' => %w[legal private],
				'meta.options' => {
					'listed' => false
				}
			).matches?(frontmatter)
		).to eq(true)
	end

	it 'requires terminal arrays and hashes to match exactly' do
		frontmatter = {
			'meta' => {
				'tags' => %w[legal private],
				'options' => {
					'listed' => false
				}
			}
		}

		expect(matcher('meta.tags' => %w[private legal]).matches?(frontmatter)).to eq(false)
		expect(matcher('meta.options' => { 'listed' => true }).matches?(frontmatter)).to eq(false)
	end

	it 'does not traverse arrays or scalar intermediate values' do
		expect(
			matcher('items.status' => 'hidden').matches?(
				'items' => [
					{ 'status' => 'hidden' }
				]
			)
		).to eq(false)
		expect(matcher('meta.status' => 'hidden').matches?('meta' => 'hidden')).to eq(false)
	end

	it 'distinguishes a present null value from a missing path' do
		null_matcher = matcher('meta.reason' => nil)

		expect(null_matcher.matches?('meta' => { 'reason' => nil })).to eq(true)
		expect(null_matcher.matches?('meta' => {})).to eq(false)
	end

	it 'requires equal values to have the same Ruby type' do
		integer_matcher = matcher('priority' => 1)
		boolean_matcher = matcher('listed' => false)

		expect(integer_matcher.matches?('priority' => 1)).to eq(true)
		expect(integer_matcher.matches?('priority' => 1.0)).to eq(false)
		expect(boolean_matcher.matches?('listed' => 'false')).to eq(false)
	end

	it 'reads symbol-keyed frontmatter without relaxing value matching' do
		expect(matcher('meta.status' => 'hidden').matches?(meta: { status: 'hidden' })).to eq(true)
		expect(matcher('meta.status' => 'hidden').matches?(meta: { status: :hidden })).to eq(false)
	end
end
