# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

class Engine

	# Writes resolved normal relationships back into document frontmatter.
	#
	# Input paths are upgraded in place while final resolved link sets are
	# written to the configured output path for each relationship pair.
	class WriteBack
		# Builds one write-back helper for the current engine instance.
		def initialize(engine:)
			@engine = engine
			@configuration = engine.configuration
			@registry = engine.registry
			@data_path = engine.data_path
		end

		# Writes every resolved normal relationship back onto the site documents.
		def write_normal_relationships!
			@configuration.collections.each do |collection|
				definitions = @configuration.normal_relationships_for(collection)
				next if definitions.empty?

				@registry.documents_for(collection).each do |document|
					write_document_relationships(document: document, definitions: definitions)
				end
			end
		end

		private

		# Writes every normal relationship path for one document.
		def write_document_relationships(document:, definitions:)
			output_paths = {}
			input_paths = {}

			definitions.each do |definition|
				state = @engine.relationship_state(document, definition.to_collection)
				next unless state

				output_path = definition.final_output_path
				output_paths[output_path] ||= []
				output_paths[output_path] << state
				definition.foreign_paths.each do |path|
					input_paths[path] ||= {
						raw_state: @engine.raw_path_state(document, path),
						definitions: []
					}
					input_paths[path][:definitions] << definition
				end
			end

			output_paths.each do |path, states|
				value = merged_output_value(states)
				@data_path.write(document.data, path, value)
				@engine.debug_logger.document_event(
					document: document,
					definitions: states.map(&:definition),
					event: 'write_output',
					details: {
						path: path,
						value: value
					}
				)
			end

			input_paths.each do |path, input_path_state|
				raw_state = input_path_state.fetch(:raw_state)
				next if output_paths.key?(path)
				next unless raw_state.present?

				value = raw_state.upgraded_value(registry: @registry)
				@data_path.write(document.data, path, value)
				@engine.debug_logger.document_event(
					document: document,
					definitions: input_path_state.fetch(:definitions),
					event: 'upgrade_input',
					details: {
						path: path,
						value: value
					}
				)
			end
		end

		# Merges one or more pair states into one final output array.
		def merged_output_value(states)
			accumulator = Jekyll::Plugins::Relationships::References::Accumulator.new(
				reference_template: @configuration.reference_template,
				multiple_settings: @configuration.multiple_settings
			)
			states.sort_by { |state| state.definition.sequence }.each do |state|
				state.current_link_entries.each do |entry|
					accumulator.add(
						document: entry.fetch(:document),
						key: entry.fetch(:key),
						metadata: entry.fetch(:metadata),
						count: entry.fetch(:count)
					)
				end
			end

			accumulator.references
		end
	end
end

end

end
end
