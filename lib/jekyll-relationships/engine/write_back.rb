# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

class Engine

	# Writes resolved normal relationships back into document frontmatter.
	#
	# Each relationship writes one final resolved link set to its configured
	# output path. Any separate ingestion paths are left untouched.
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

			definitions.each do |definition|
				state = @engine.relationship_state(document, definition.to_collection)
				next unless state

				output_path = definition.final_output_path
				output_paths[output_path] ||= []
				output_paths[output_path] << state
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
	end
end

end

end
end
