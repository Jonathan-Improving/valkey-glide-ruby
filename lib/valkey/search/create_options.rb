# frozen_string_literal: true

class Valkey
  module Search
    # Index-level options for FT.CREATE (everything before SCHEMA). Mirrors the
    # Java FTCreateOptions.
    #
    # @example
    #   Valkey::Search::CreateOptions.new(on: :hash, prefixes: ["doc:"], skip_initial_scan: true)
    #
    # @see https://redis.io/commands/ft.create/
    class CreateOptions
      # @param on [Symbol, String, nil] :hash or :json (ON clause)
      # @param prefixes [Array<String>, nil] key prefixes (`PREFIX <count> <p...>`)
      # @param score [Numeric, nil] default document score
      # @param language [String, nil] default stemmer language
      # @param skip_initial_scan [Boolean] emit SKIPINITIALSCAN
      # @param min_stem_size [Integer, nil] emit `MINSTEMSIZE <n>`
      # @param stopwords [Array<String>, nil] custom stopwords (mutually exclusive with no_stopwords)
      # @param no_stopwords [Boolean] emit NOSTOPWORDS
      # @param filter [String, nil] a filter expression limiting which
      #   documents the index applies to (valkey-search 1.3.0). A document
      #   that doesn't match this expression is excluded from the index even
      #   if its key matches a configured prefix. Cannot be empty.
      # @param score_field [String, nil] the name of a document field whose
      #   numeric value is used as the document's custom score, multiplying
      #   into the final relevance score (valkey-search 1.3.0). The field
      #   must already exist in the document; it is not itself a schema
      #   definition. FT.INFO only reports this back under
      #   `index_definition`'s `score_field` key when `search.emulate-release`
      #   is at least 1.3.0 — below that level the pair is omitted entirely.
      # @param no_highlight [Boolean] emit NOHL. valkey-search does not
      #   support highlighting at all, so this is a genuine no-op on this
      #   engine (the token is accepted but not even stored for FT.INFO to
      #   report). Included for wire compatibility with RediSearch clients.
      # @raise [ArgumentError] if filter is an empty String, or stopwords
      #   and no_stopwords are both set
      def initialize(on: nil, prefixes: nil, score: nil, language: nil,
                     skip_initial_scan: false, min_stem_size: nil,
                     stopwords: nil, no_stopwords: false, filter: nil,
                     score_field: nil, no_highlight: false)
        raise ArgumentError, "stopwords and no_stopwords are mutually exclusive" if !stopwords.nil? && no_stopwords
        raise ArgumentError, "filter cannot be empty" if !filter.nil? && filter.empty?

        @on = on.nil? ? nil : normalize_on(on)
        @prefixes = prefixes
        @score = score
        @language = language
        @skip_initial_scan = skip_initial_scan
        @min_stem_size = min_stem_size
        @stopwords = stopwords
        @no_stopwords = no_stopwords
        @filter = filter
        @score_field = score_field
        @no_highlight = no_highlight
      end

      # @return [Array] FT.CREATE option tokens (before SCHEMA)
      def to_args
        args = []
        args.push("ON", @on) unless @on.nil?
        args.push("PREFIX", @prefixes.length, *@prefixes) if @prefixes && !@prefixes.empty?
        args.push("SCORE", @score) unless @score.nil?
        args.push("LANGUAGE", @language) unless @language.nil?
        args << "SKIPINITIALSCAN" if @skip_initial_scan
        args.push("MINSTEMSIZE", @min_stem_size) unless @min_stem_size.nil?
        args.push("STOPWORDS", @stopwords.length, *@stopwords) if @stopwords && !@stopwords.empty?
        args << "NOSTOPWORDS" if @no_stopwords
        args.push("FILTER", @filter) unless @filter.nil?
        args.push("SCORE_FIELD", @score_field) unless @score_field.nil?
        args << "NOHL" if @no_highlight
        args
      end

      private

      def normalize_on(on)
        Search.lookup_token(Search::DATA_TYPES, on, "data type")
      end
    end
  end
end
