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

				documents_for(collection).each do |document|
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
				ensure_output_path_can_receive_consolidated_links!(
					document: document,
					path: path,
					definitions: states.map(&:definition)
				)
				value = merged_output_value(states)
				@data_path.write(document.data, path, value)
				@engine.debug_logger.document_event(
					document: document,
					definitions: states.map(&:definition),
					area: 'upgrading',
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

				raw_state.write_upgraded_input!(
					registry: @registry,
					active_document_checker: proc { |resolved_document| active_document?(resolved_document) }
				)
				value = raw_state.upgraded_raw_value(
					registry: @registry,
					active_document_checker: proc { |resolved_document| active_document?(resolved_document) }
				)
				@engine.debug_logger.document_event(
					document: document,
					definitions: input_path_state.fetch(:definitions),
					area: 'upgrading',
					event: 'upgrade_input',
					details: {
						path: path,
						value: value
					}
				)
			end
		end

		# Rejects any consolidated output path that expands through arrays.
		def ensure_output_path_can_receive_consolidated_links!(document:, path:, definitions:)
			path_state = @data_path.read_result(document.data, path)
			return unless path_state.array_traversed?

			relationship_descriptions = definitions.uniq.map do |definition|
				"#{definition.from_collection} -> #{definition.to_collection}"
			end.join(', ')
			raise ResolutionError, "Cannot write consolidated relationships for `#{document.relative_path}` to frontmatter path `#{path}` because that path spans across an array. Configure `frontmatter.output` to a separate hash path for #{relationship_descriptions}."
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

		# Returns every document visible to the active engine or session.
		def documents_for(collection)
			return @engine.documents_for(collection) if @engine.respond_to?(:documents_for)

			@registry.documents_for(collection)
		end

		# Returns true when one document is active in the current engine or session.
		def active_document?(document)
			return @engine.active_document?(document) if @engine.respond_to?(:active_document?)

			true
		end
	end
end

end

end
end
