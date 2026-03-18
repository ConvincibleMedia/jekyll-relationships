# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Jekyll::Plugins::Relationships::Support do
	describe '.hash_deep_merge' do
		it 'deep-merges the second hash onto the first hash' do
			merged = described_class.hash_deep_merge(
				{
					'alpha' => 1,
					'nested' => {
						'keep' => 'left',
						'left_only' => true
					}
				},
				{
					beta: 2,
					'nested' => {
						'keep' => 'right',
						'right_only' => true
					}
				}
			)

			expect(merged).to eq({
				'alpha' => 1,
				'beta' => 2,
				'nested' => {
					'keep' => 'right',
					'left_only' => true,
					'right_only' => true
				}
			})
		end

		it 'treats non-hash values as leaf replacements' do
			merged = described_class.hash_deep_merge(
				{
					'alpha' => {
						'nested' => true
					}
				},
				{
					'alpha' => 'override'
				}
			)

			expect(merged).to eq({
				'alpha' => 'override'
			})
		end
	end
end
