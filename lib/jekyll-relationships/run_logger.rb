# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

# Emits the default high-level summary lines for relationship processing.
#
# This logger stays separate from debug logging so the engine can always report
# the configured relationship coverage, prune removals, and total run time
# without mixing that output into the lower-level trace areas.
class RunLogger
	MAX_REMOVED_FILENAME_CHARACTERS = 50
	NON_BREAKING_SPACE = "\u00a0"

	# Builds one summary logger for one engine run.
	def initialize
		@started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
	end

	# Logs one multi-line summary of the configured relationships.
	def relationship_summary(lines:, relationship_count:)
		log_lines(
			header: "#{relationship_count} relationships defined.",
			lines: lines
		)
	end

	# Logs one multi-line summary of the documents removed by pruning.
	def pruning_summary(removed_documents_by_collection:)
		total_removed = removed_documents_by_collection.values.flatten.length
		lines = removed_documents_by_collection.keys.sort.map do |collection|
			documents = removed_documents_by_collection.fetch(collection)
			"#{collection}:#{NON_BREAKING_SPACE} #{documents.length} removed (#{removed_filenames(documents)})"
		end
		log_lines(
			header: "Removed #{total_removed} items because of pruning rules.",
			lines: lines
		)
	end

	# Logs the total elapsed time for relationship processing.
	def finish!
		elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at
		Jekyll.logger.info('Relationships:', format('Done in %.2f seconds.', elapsed))
	end

	private

	# Writes one heading plus a tree-shaped list of lines.
	def log_lines(header:, lines:)
		Jekyll.logger.info('Relationships:', header)
		lines.each_with_index do |line, index|
			branch = index == lines.length - 1 ? '└─' : '├─'
			Jekyll.logger.info('Relationships:', "#{branch} #{line}")
		end
	end

	# Builds one truncated filename list for the removed-documents summary.
	def removed_filenames(documents)
		filenames = Array(documents).map do |document|
			File.basename(document.relative_path)
		end.sort
		return '' if filenames.empty?

		included_names = []
		character_total = 0

		filenames.each do |filename|
			next_total = character_total + filename.length
			break if !included_names.empty? && next_total > MAX_REMOVED_FILENAME_CHARACTERS

			included_names << filename
			character_total = next_total
		end

		text = included_names.join(', ')
		return text if included_names.length == filenames.length

		"#{text}, ..."
	end
end

end

end
end
