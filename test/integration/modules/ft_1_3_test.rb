# frozen_string_literal: true

require "test_helper"

# Runs valkey-search 1.3 FT.* tests against a REAL valkey-search module via
# Docker (utils/run-modules-ci-locally.sh), in addition to (not instead of)
# the vendored RediSearch .so test/lint/vector_search_commands.rb exercises
# (PG-14: no module-test harness existed in this repo before this port).
#
# Gated by the capability probe (Helper::SearchCapability) rather than a
# version-string compare: on valkey-bundle:9.1.3 (search 1.2.1) every test
# in this class skips with a stated reason (D1). Against the rc2 .so from
# BUILD-MODULES-1.3.md, tests further branch on the active
# search.emulate-release level (the level fixture) to assert the corrected
# 1.3 behavior only when that level is actually >= 1.3.0 (D22) — a
# 1.3-capable module left at its own default (1.0.0) still runs the legacy
# branch of every VALKEY_SEARCH_COMPATIBILITY_FIX gate.
#
# Run via: utils/run-modules-ci-locally.sh (sets MODULES_STANDALONE_ENDPOINT
# / MODULES_CLUSTER_ENDPOINTS and invokes `rake test:modules`). Running this
# file directly without that harness fails loudly (no endpoints configured),
# rather than silently falling back to the main suite's vendored-.so fixture.
class ModulesFt13Test < Minitest::Test
  include Helper::ModuleClient

  def setup
    @client = modules_standalone_client
    @capable = Helper::SearchCapability.probe_1_3_capability(@client)
    @level = @capable ? Helper::SearchCapability.emulate_release_level(@client) : nil
    @index = "modules_ft13_#{SecureRandom.hex(4)}"
  end

  def teardown
    @client.send_command(Valkey::RequestType::CUSTOM_COMMAND, ["FT.DROPINDEX", @index])
  rescue Valkey::CommandError
    nil
  ensure
    @client&.close
  end

  def skip_unless_1_3!
    skip "search module is pre-1.3 (search.emulate-release unavailable); 1.3 tests skip on this build" unless @capable
  end

  def skip_unless_emulate_release_1_3!
    skip_unless_1_3!
    return if @level && Helper::Version.new(@level) >= Helper::Version.new("1.3.0")

    skip "search.emulate-release is #{@level.inspect}, not >= 1.3.0; the corrected 1.3 " \
         "behavior requires search.emulate-release 1.3.0 (D22) — GLIDE stays a pass-through"
  end

  # ---- capability probe / level fixture plumbing ----

  def test_capability_probe_runs_without_raising
    refute_nil @capable
  end

  def test_level_fixture_reads_a_value_when_1_3_capable
    skip_unless_1_3!
    refute_nil @level, "a 1.3-capable module must report a search.emulate-release level"
  end

  # ---- wave 1 core: INKEYS, bare wildcard, auto-load ----

  def test_in_keys_restricts_search_to_given_keys
    skip_unless_1_3!
    create_basic_index
    @client.hset("doc:1", "title", "hello")
    @client.hset("doc:2", "title", "hello")
    result = @client.ft_search(@index, "*", in_keys: ["doc:1"])
    assert_equal 1, result.total_results
    assert_equal ["doc:1"], result.documents.map(&:key)
  end

  def test_bare_wildcard_matches_every_document
    skip_unless_1_3!
    create_basic_index
    @client.hset("doc:1", "title", "hello")
    result = @client.ft_search(@index, "*")
    assert_equal 1, result.total_results
  end

  # ---- scoring ----

  def test_with_scores_and_scorer
    skip_unless_1_3!
    create_basic_index
    @client.hset("doc:1", "title", "hello world")
    raw = @client.call("FT.SEARCH", @index, "hello", "WITHSCORES", "SCORER", "BM25STD")
    assert_kind_of Array, raw
  end

  def test_count_option_emits_limit_zero_zero_and_returns_total_only
    skip_unless_1_3!
    create_basic_index
    @client.hset("doc:1", "title", "hello")
    @client.hset("doc:2", "title", "hello")
    result = @client.ft_search(@index, "*", count: true)
    assert_equal 2, result.total_results
    assert_empty result.documents
  end

  # ---- cursors (D15: pinned to the index slot's primary) ----

  def test_aggregate_with_cursor_pages_results
    skip_unless_1_3!
    create_basic_index
    5.times { |i| @client.hset("doc:#{i}", "title", "hello") }
    rows, cursor_id = @client.ft_aggregate(
      @index, "*",
      load: ["__key"],
      with_cursor: Valkey::Search::WithCursor.new(count: 2)
    )
    assert_equal 2, rows.length
    refute_equal 0, cursor_id

    next_rows, next_cursor_id = @client.ft_cursor_read(@index, cursor_id)
    assert_equal 2, next_rows.length
    @client.ft_cursor_del(@index, next_cursor_id) unless next_cursor_id.zero?
  end

  # ---- FT.HYBRID: the port-rules-mandated FILTER-right-after-VSIM-arm case ----

  def test_hybrid_filter_immediately_after_vsim_arm_is_not_claimed_as_vsim_prefilter
    skip_unless_1_3!
    create_vector_index
    @client.hset("doc:1", "title", "hello world", "price", "10")
    @client.hset("doc:2", "title", "hello world", "price", "-5")
    vector = [0.1, 0.2, 0.3, 0.4].pack("f*")

    # A FILTER clause with no LOAD in between the VSIM arm and the clause:
    # if PARAMS isn't emitted first, the server's VSIM parser claims this
    # FILTER as its own pre-filter instead of an aggregate-pipeline FILTER,
    # and the price>0 condition would never apply. jamesx's #7335 review
    # finding; the regression only reproduces without a LOAD in between.
    rows = @client.ft_hybrid(
      @index,
      Valkey::Search::HybridSearchArm.new("hello world"),
      Valkey::Search::HybridVsimArm.new("vec", vector, k: 10),
      Valkey::Search::HybridOptions.new(
        load_fields: ["price"],
        clauses: [Valkey::Search::Filter.new("@price > 0")]
      )
    )
    refute_empty rows
    assert(rows.all? { |row| row["price"].to_f.positive? })
  end

  private

  def create_basic_index
    @client.ft_create(@index, [Valkey::Search::TextField.new("title", sortable: true)], on: :hash)
  end

  def create_vector_index
    @client.ft_create(
      @index,
      [
        Valkey::Search::TextField.new("title"),
        Valkey::Search::NumericField.new("price"),
        Valkey::Search::VectorField.flat("vec", dim: 4, metric: :l2)
      ],
      on: :hash
    )
  end
end
