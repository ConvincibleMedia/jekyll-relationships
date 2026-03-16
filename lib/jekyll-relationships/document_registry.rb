# frozen_string_literal: true

module Jekyll
module Plugins

module Relationships

# Indexes participating documents by collection and primary key.
#
# Indices are built lazily per primary-key path so relationship definitions can
# use different key schemes without rebuilding unrelated lookups.
class DocumentRegistry

	# Builds the registry over the collections used by the configuration.
	def initialize(site:, collections:)
		@site = site
		@collections = collections
		@indices_by_primary_path = {}
	end

	# Returns true when the document belongs to one of the tracked collections.
	def participating?(document)
		@collections.include?(collection_label(document))
	end

	# Returns the collection label for one document.
	def collection_label(document)
		document.collection.label
	end

	# Returns all participating documents for one collection.
	def documents_for(collection)
		site_collection = @site.collections[collection]
		return [] unless site_collection

		site_collection.docs
	end

	# Computes the active primary key for one document and scheme.
	def key_for(document, primary_path:)
		if primary_path.nil?
			default_relative_key(document)
		else
			value = Jekyll::Plugins::Relationships::Support::DataPath.new.read(document.data, primary_path)
			raise ResolutionError, "Document `#{document.relative_path}` is missing primary key path `#{primary_path}`." if value.nil?

			value.to_s
		end
	end

	# Resolves one key to a document, optionally constrained to a collection.
	def lookup(key:, primary_path:, collection: nil)
		index = index_for(primary_path)
		if collection
			document = fetch_nested(index.fetch(:by_collection), collection, key.to_s)
			raise ResolutionError, "Could not resolve key `#{key}` in collection `#{collection}`." unless document

			return document
		end

		matches = index.fetch(:by_key).fetch(key.to_s, [])
		raise ResolutionError, "Could not resolve key-only reference `#{key}`." if matches.empty?
		return matches.first if index.fetch(:site_wide_unique)
		return matches.first if matches.length == 1

		collections = matches.map { |document| collection_label(document) }.uniq.sort.join(', ')
		raise ResolutionError, "Key-only reference `#{key}` is ambiguous across collections: #{collections}."
	end

	private

	# Returns or builds the index for one primary-key scheme.
	def index_for(primary_path)
		signature = primary_path.nil? ? '__relative_path__' : primary_path
		@indices_by_primary_path[signature] ||= build_index(primary_path)
	end

	# Builds the collection and global indices for one scheme.
	def build_index(primary_path)
		by_collection = Hash.new { |hash, key| hash[key] = {} }
		by_key = Hash.new { |hash, key| hash[key] = [] }

		@collections.each do |collection|
			documents_for(collection).each do |document|
				key = key_for(document, primary_path: primary_path)
				if by_collection[collection].key?(key)
					raise ResolutionError, "Primary key `#{key}` is duplicated within collection `#{collection}`."
				end

				by_collection[collection][key] = document
				by_key[key] << document
			end
		end

		{
			by_collection: by_collection,
			by_key: by_key,
			site_wide_unique: by_key.values.all? { |documents| documents.length <= 1 }
		}
	end

	# Reads one nested hash value without creating a default entry.
	def fetch_nested(hash, first_key, second_key)
		first_hash = hash[first_key]
		return nil unless first_hash

		first_hash[second_key]
	end

	# Implements the README's default relative-path key rule.
	def default_relative_key(document)
		document.relative_path.sub(/\A_/, '').sub(/#{Regexp.escape(document.extname)}\z/, '')
	end
end

end

end
end
