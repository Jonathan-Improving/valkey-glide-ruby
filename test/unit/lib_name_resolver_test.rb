# frozen_string_literal: true

require "test_helper"

# Unit tests for Valkey.resolve_lib_name — the pure resolver behind the
# `CLIENT SETINFO LIB-NAME` value. These do not require a running server or the
# FFI: they cover the whole composition matrix in the Ruby layer only.
#
# Character validity is intentionally NOT tested here, because it is not the
# wrapper's concern — glide-core validates the composed name before client
# creation (valkey-io/valkey-glide#6891). What is tested is composition and the
# empty-means-absent normalization, which the wrapper does own.
class TestLibNameResolverUnit < Minitest::Test
  def test_default_when_nothing_configured
    assert_equal "GlideRuby", Valkey.resolve_lib_name
  end

  def test_default_constant_matches_resolved_default
    assert_equal Valkey::DEFAULT_LIB_NAME, Valkey.resolve_lib_name
  end

  def test_lib_name_override
    assert_equal "CustomLib", Valkey.resolve_lib_name(lib_name: "CustomLib")
  end

  def test_tag_only_appends_to_default
    assert_equal "GlideRuby(tag)", Valkey.resolve_lib_name(client_info_tag: "tag")
  end

  def test_lib_name_and_tag_combine
    assert_equal "CustomLib(tag)", Valkey.resolve_lib_name(lib_name: "CustomLib", client_info_tag: "tag")
  end

  # An empty string is truthy in Ruby, so each empty form needs its own guard.
  # Empty means "not configured", matching glide-core's empty-means-absent rule.

  def test_empty_lib_name_falls_back_to_default
    assert_equal "GlideRuby", Valkey.resolve_lib_name(lib_name: "")
  end

  def test_empty_tag_produces_no_suffix
    assert_equal "GlideRuby", Valkey.resolve_lib_name(client_info_tag: "")
  end

  def test_both_empty_falls_back_to_default
    assert_equal "GlideRuby", Valkey.resolve_lib_name(lib_name: "", client_info_tag: "")
  end

  # Regression: an empty override with a tag previously composed "(tag)", which
  # glide-core rejects because the name must not start with a parenthesis.
  def test_empty_lib_name_with_tag_uses_default_base
    assert_equal "GlideRuby(tag)", Valkey.resolve_lib_name(lib_name: "", client_info_tag: "tag")
  end

  def test_lib_name_with_empty_tag_produces_no_suffix
    assert_equal "CustomLib", Valkey.resolve_lib_name(lib_name: "CustomLib", client_info_tag: "")
  end

  def test_never_composes_empty_parentheses
    ["", nil].each do |tag|
      refute_includes Valkey.resolve_lib_name(lib_name: "CustomLib", client_info_tag: tag), "()"
    end
  end

  def test_non_string_values_are_coerced
    assert_equal "GlideRuby(42)", Valkey.resolve_lib_name(client_info_tag: 42)
  end
end
