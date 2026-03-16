# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

# Orchestrates configuration parsing, resolution, and final write-back.
#
# One engine instance handles one Jekyll build and owns all mutable state used
# while relationships are resolved recursively.
class Engine

	# Captures one raw foreign-path input on one document.
	#
# The state parses and caches the original reference entries so multiple
# relationship pairs can reuse the same input path without re-reading the file.
	class RawPathState
		attr_reader :document, :path

		# Builds one raw-path cache for one document and path.
		def initialize(document:, path:, data_path:, string_array:, reference_template:)
			@document = document
			@path = path
			@data_path = data_path
			@string_array = string_array
			@reference_template = reference_template
			@raw_value = @data_path.read(@document.data, @path)
			@present = !@raw_value.nil?
			@shape = infer_shape(@raw_value)
			@entries = parse_entries(@raw_value)
			@resolution_cache = {}
			@preferred_primary_path = nil
		end

		# Returns true when the source path existed in frontmatter.
		def present?
			@present
		end

		# Resolves every entry for one primary-key scheme.
		def resolved_entries_for(primary_path, registry)
			signature = primary_signature(primary_path)
			@preferred_primary_path ||= primary_path
			@resolution_cache[signature] ||= @entries.map do |entry|
				resolve_entry(entry, primary_path, registry)
			end
		end

		# Builds the upgraded original-path value for write-back.
		def upgraded_value(registry)
			return nil unless present?

			signature = primary_signature(@preferred_primary_path)
			resolved_entries = @resolution_cache[signature] || []
			values = []
			seen_documents = Set.new

			@entries.each_with_index do |entry, index|
				resolved_entry = resolved_entries[index]
				if resolved_entry
					next if seen_documents.include?(resolved_entry.fetch(:document).object_id)

					seen_documents << resolved_entry.fetch(:document).object_id
					values << build_reference_hash(resolved_entry)
				else
					values << entry.original_value
				end
			end

			return values if @shape == :array || values.length != 1

			values.first
		end

		private

		# Parses one raw frontmatter value into reference entries.
		def parse_entries(raw_value)
			@string_array.interpret(raw_value, split: -1, flatten: true).map do |entry|
				@reference_template.parse(entry)
			end.compact
		end

		# Resolves one parsed entry to a real document and its canonical key.
		def resolve_entry(entry, primary_path, registry)
			document = if entry.document?
									 entry.page
								 else
									 registry.lookup(
										 key: entry.key,
										 primary_path: primary_path,
										 collection: entry.collection.nil? ? nil : entry.collection.to_s
									 )
								 end

			{
				document: document,
				key: registry.key_for(document, primary_path: primary_path),
				metadata: entry.metadata
			}
		end

		# Builds one output reference hash from a resolved entry.
		def build_reference_hash(resolved_entry)
			@reference_template.build(
				document: resolved_entry.fetch(:document),
				key: resolved_entry.fetch(:key),
				metadata: resolved_entry.fetch(:metadata)
			)
		end

		# Normalises the cache key for a primary scheme.
		def primary_signature(primary_path)
			primary_path.nil? ? '__relative_path__' : primary_path
		end

		# Tracks the original top-level shape of a path value.
		def infer_shape(raw_value)
			raw_value.is_a?(Array) ? :array : :single
		end
	end

	# Tracks the mutable link set for one document and concrete relationship.
	#
# Relationship states are the unit of recursive resolution: each state is
# resolved at most once, and cyclic attempts to re-enter it raise an error.
	class RelationshipState
		attr_reader :document, :definition

		# Builds one new state for one document-to-collection pair.
		def initialize(engine:, document:, definition:)
			@engine = engine
			@document = document
			@definition = definition
			@status = :unseen
			@raw_seeded = false
			@links_by_document_id = {}
			@link_order = []
		end

		# Returns true while the state is actively being resolved.
		def resolving?
			@status == :resolving
		end

		# Returns true after the state has fully resolved.
		def resolved?
			@status == :resolved
		end

		# Resolves the state unless it has already been handled.
		def resolve!
			return if resolved?
			raise ResolutionError, "Cyclic relationship resolution detected while resolving #{description}." if resolving?

			@status = :resolving
			seed_raw_links!
			run_resolvers!
			@status = :resolved
		end

		# Adds one link to the state and mirrors it when required.
		def link(reference, metadata: nil, reflect: true)
			target_document = @engine.resolve_reference_document(
				reference,
				primary_path: @definition.primary_path,
				collection_hint: @definition.to_collection
			)
			unless target_document.collection.label == @definition.to_collection
				raise ResolutionError, "Resolver attempted to link `#{target_document.relative_path}` outside the allowed target collection `#{@definition.to_collection}`."
			end

			document_id = target_document.object_id
			return if @links_by_document_id.key?(document_id)

			@links_by_document_id[document_id] = {
				document: target_document,
				metadata: sanitised_metadata(metadata)
			}
			@link_order << document_id

			return unless reflect && @definition.bidirectional

			@engine.mirror_add(source_state: self, target_document: target_document, metadata: metadata)
		end

		# Removes one link, or every link when no reference is given.
		def unlink(reference = nil, reflect: true)
			if reference.nil?
				@link_order.dup.each do |document_id|
					remove_document_id(document_id, reflect: reflect)
				end
				return
			end

			target_document = @engine.resolve_reference_document(
				reference,
				primary_path: @definition.primary_path,
				collection_hint: @definition.to_collection
			)
			remove_document_id(target_document.object_id, reflect: reflect)
		end

		# Returns the current resolved reference hashes.
		def current_references
			current_link_payloads.map { |payload| payload.fetch(:reference) }
		end

		# Returns current link payloads including target documents.
		def current_link_payloads
			@link_order.each_with_object([]) do |document_id, payloads|
				entry = @links_by_document_id[document_id]
				next unless entry

				target_document = entry.fetch(:document)
				payloads << {
					document: target_document,
					reference: @engine.configuration.reference_template.build(
						document: target_document,
						key: @engine.registry.key_for(target_document, primary_path: @definition.primary_path),
						metadata: entry.fetch(:metadata)
					)
				}
			end
		end

		private

		# Seeds the state from raw frontmatter once.
		def seed_raw_links!
			return unless @definition.reads_frontmatter
			return if @raw_seeded

			@definition.foreign_paths.each do |path|
				raw_state = @engine.raw_path_state(@document, path)
				next unless raw_state.present?

				raw_state.resolved_entries_for(@definition.primary_path, @engine.registry).each do |entry|
					next unless entry
					next unless entry.fetch(:document).collection.label == @definition.to_collection

					link(entry.fetch(:document), metadata: entry.fetch(:metadata), reflect: @definition.bidirectional)
				end
			end

			@raw_seeded = true
		end

		# Instantiates and runs all configured resolver classes.
		def run_resolvers!
			@definition.resolver_classes.each do |resolver_class|
				resolver_class.new(engine: @engine, state: self).resolve
			end
		end

		# Removes one stored document id and mirrors the removal if needed.
		def remove_document_id(document_id, reflect:)
			entry = @links_by_document_id.delete(document_id)
			return unless entry

			@link_order.delete(document_id)
			return unless reflect && @definition.bidirectional

			@engine.mirror_remove(source_state: self, target_document: entry.fetch(:document))
		end

		# Removes engine-reserved properties from resolver metadata.
		def sanitised_metadata(metadata)
			return {} unless metadata.is_a?(Hash)

			metadata.each_with_object({}) do |(property, value), filtered|
				string_property = property.to_s
				next if @engine.configuration.reference_template.reserved_properties.include?(string_property)

				filtered[string_property] = value
			end
		end

		# Builds a human-readable state label for errors.
		def description
			"`#{@document.relative_path}` (#{@definition.from_collection} -> #{@definition.to_collection})"
		end
	end

	attr_reader :site, :configuration, :registry, :tree_graph

	# Builds one engine for one Jekyll site build.
	def initialize(site:)
		@site = site
		@configuration = Configuration.new(@site.config)
		@registry = DocumentRegistry.new(site: @site, collections: @configuration.collections)
		@data_path = Jekyll::Plugins::Relationships::Support::DataPath.new
		@string_array = Jekyll::Plugins::Support::StringArray.new
		@tree_graph = TreeGraph.new(
			site: @site,
			configuration: @configuration,
			registry: @registry,
			data_path: @data_path
		)
		@raw_path_states = {}
		@relationship_states = {}
		@document_resolution_states = {}
	end

	# Processes the whole site.
	def process!
		return if @configuration.collections.empty?

		@tree_graph.build!
		resolve_all_relationships!
		write_back_normal_relationships!
		@tree_graph.write_back!
	end

	# Returns the cached raw-path state for one document and path.
	def raw_path_state(document, path)
		@raw_path_states[[document.object_id, path]] ||= RawPathState.new(
			document: document,
			path: path,
			data_path: @data_path,
			string_array: @string_array,
			reference_template: @configuration.reference_template
		)
	end

	# Resolves and returns one relationship array.
	def resolve_relationships(document, to_collection)
		state = relationship_state(document, to_collection)
		return [] unless state

		resolve_state(state)
		state.current_references
	end

	# Resolves every outgoing pair for one document.
	def resolve_document(document)
		return document unless @registry.participating?(document)

		document_id = document.object_id
		status = @document_resolution_states[document_id]
		raise ResolutionError, "Cyclic document resolution detected for `#{document.relative_path}`." if status == :resolving
		return document if status == :resolved

		@document_resolution_states[document_id] = :resolving
		@configuration.normal_relationships_for(document.collection.label).each do |definition|
			resolve_relationships(document, definition.to_collection)
		end
		@document_resolution_states[document_id] = :resolved
		document
	end

	# Resolves one helper or resolver reference to a document.
	def resolve_reference_document(reference, primary_path:, collection_hint: nil)
		return reference if reference.is_a?(Jekyll::Document)

		parsed_reference = @configuration.reference_template.parse(reference)
		return parsed_reference.page if parsed_reference.document?

		@registry.lookup(
			key: parsed_reference.key,
			primary_path: primary_path,
			collection: collection_hint || (parsed_reference.collection.nil? ? nil : parsed_reference.collection.to_s)
		)
	end

	# Mirrors one bidirectional add into the reverse state.
	def mirror_add(source_state:, target_document:, metadata:)
		mirror_state = relationship_state(target_document, source_state.definition.from_collection)
		return unless mirror_state

		mirror_state.link(source_state.document, metadata: metadata, reflect: false)
	end

	# Mirrors one bidirectional removal into the reverse state.
	def mirror_remove(source_state:, target_document:)
		mirror_state = relationship_state(target_document, source_state.definition.from_collection)
		return unless mirror_state

		mirror_state.unlink(source_state.document, reflect: false)
	end

	private

	# Resolves every configured normal relationship state once.
	def resolve_all_relationships!
		@configuration.collections.each do |collection|
			definitions = @configuration.normal_relationships_for(collection)
			next if definitions.empty?

			@registry.documents_for(collection).each do |document|
				definitions.each do |definition|
					resolve_relationships(document, definition.to_collection)
				end
			end
		end
	end

	# Writes both upgraded raw input paths and final output arrays.
	def write_back_normal_relationships!
		@configuration.collections.each do |collection|
			definitions = @configuration.normal_relationships_for(collection)
			next if definitions.empty?

			@registry.documents_for(collection).each do |document|
				write_back_document_relationships(document, definitions)
			end
		end
	end

	# Writes every normal relationship path for one document.
	def write_back_document_relationships(document, definitions)
		output_paths = {}
		input_paths = {}

		definitions.each do |definition|
			state = relationship_state(document, definition.to_collection)
			next unless state

			output_path = definition.final_output_path
			output_paths[output_path] ||= []
			output_paths[output_path] << state
			definition.foreign_paths.each do |path|
				input_paths[path] = raw_path_state(document, path)
			end
		end

		output_paths.each do |path, states|
			@data_path.write(document.data, path, merged_output_value(states))
		end

		input_paths.each do |path, raw_state|
			next if output_paths.key?(path)
			next unless raw_state.present?

			@data_path.write(document.data, path, raw_state.upgraded_value(@registry))
		end
	end

	# Merges one or more pair states into one final output array.
	def merged_output_value(states)
		seen_documents = Set.new
		states.sort_by { |state| state.definition.sequence }.each_with_object([]) do |state, merged|
			state.current_link_payloads.each do |payload|
				document_id = payload.fetch(:document).object_id
				next if seen_documents.include?(document_id)

				seen_documents << document_id
				merged << payload.fetch(:reference)
			end
		end
	end

	# Returns the cached relationship state for one concrete pair.
	def relationship_state(document, to_collection)
		definition = @configuration.normal_relationship_for(
			from_collection: document.collection.label,
			to_collection: to_collection
		)
		return nil unless definition

		@relationship_states[[document.object_id, to_collection]] ||= RelationshipState.new(
			engine: self,
			document: document,
			definition: definition
		)
	end

	# Resolves one relationship state with cycle detection.
	def resolve_state(state)
		return state if state.resolved?
		raise ResolutionError, "Cyclic relationship resolution detected while resolving `#{state.document.relative_path}`." if state.resolving?

		state.resolve!
		state
	end
end

end

end
end
