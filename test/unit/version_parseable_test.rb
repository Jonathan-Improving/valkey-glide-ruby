# frozen_string_literal: true

require "test_helper"

# Unit tests for Helper::Version.parseable? — the predicate that screens server
# version strings before they are trusted for version gating.
#
# This guard shipped without tests in an earlier round, and a table like this one
# would have immediately surfaced that the regex was end-unanchored (so
# "8garbage" gated tests to RUN) and that it admitted "0"/"0.0" (the sentinel
# values whose removal the guard exists to make permanent).
#
# Why this matters more than it looks: Version comparison is lenient by design —
# `<=>` compares parts with #to_i, so a non-numeric part becomes 0 and an
# unparseable string sorts BELOW every real version. Garbage therefore WINS a
# minimum, so a single bad node can drag a whole cluster's version gates down to
# "skip". A skipped test and a passing test look identical in suite output, so a
# hole here is silent.
class TestVersionParseableUnit < Minitest::Test
  # Real-world forms that must be usable.
  ACCEPTED = [
    "8",
    "8.1",
    "8.1.0",
    "7.2",
    "9.1.1",
    "10.0.0",
    "8.1.0-rc1",
    "8.1.0-alpha.2"
  ].freeze

  # Everything that must NOT be trusted as a version.
  REJECTED = [
    "",             # a valueless INFO line yields this via HashifyInfo
    "unstable",
    "0",            # sentinel shape
    "0.0",          # verbatim the removed sentinel
    "00",
    "0garbage",
    "7.1garbage",
    "8garbage",     # end-unanchored regex gated this to RUN: a false PASS
    "8.1.0.",
    "8.1.0-",
    "-1.0",
    "v8.1.0",
    " 8.1.0",
    "8.1.0 "
  ].freeze

  ACCEPTED.each do |value|
    define_method(:"test_accepts_#{value.gsub(/\W/, '_')}") do
      assert Helper::Version.parseable?(value), "expected #{value.inspect} to be usable"
    end
  end

  REJECTED.each do |value|
    define_method(:"test_rejects_#{value.empty? ? 'empty_string' : value.gsub(/\W/, '_')}") do
      refute Helper::Version.parseable?(value), "expected #{value.inspect} to be rejected"
    end
  end

  def test_rejects_nil
    refute Helper::Version.parseable?(nil)
  end

  def test_rejects_non_string_types
    [42, 8.1, :'8.1.0', [], {}, true].each do |value|
      refute Helper::Version.parseable?(value), "expected #{value.inspect} to be rejected"
    end
  end

  def test_rejects_a_version_instance
    # Callers screen raw strings from INFO; accepting a Version here would let a
    # pre-wrapped sentinel through the same hole.
    refute Helper::Version.parseable?(Helper::Version.new("8.1.0"))
  end

  # The property the predicate exists to protect: nothing it accepts may sort at
  # or below the sentinel it replaced.
  def test_nothing_accepted_sorts_at_or_below_the_old_sentinel
    ACCEPTED.each do |value|
      assert Helper::Version.new(value) > Helper::Version.new("0.0"),
             "#{value.inspect} must sort above the old \"0.0\" sentinel"
    end
  end

  # Documents a known comparison quirk rather than asserting it is desirable: a
  # pre-release compares EQUAL to its GA version, so an rc satisfies its own GA
  # gate. Acceptable here (an rc of 7.2 does have 7.2 behaviour) but surprising
  # enough to pin so a future change is deliberate.
  def test_prerelease_compares_equal_to_its_ga_version
    assert_equal 0, Helper::Version.new("8.1.0-rc1") <=> Helper::Version.new("8.1.0")
  end
end
