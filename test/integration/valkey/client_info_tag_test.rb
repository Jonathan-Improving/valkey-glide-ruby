# frozen_string_literal: true

# Tests for client_info_tag and lib_name configuration options.
#
# These options control the CLIENT SETINFO LIB-NAME value sent during
# connection establishment. client_info_tag appends a parenthesized tag
# to the default library name (GlideRuby), while lib_name provides a
# full override.
#
# Reference: valkey-io/valkey-glide#6389 (Python implementation)
module ValkeyTests
  module ClientInfoTag
    # --- Validation tests (no server needed) ---

    def test_client_info_tag_rejects_empty_string
      error = assert_raises(ArgumentError) do
        Valkey.new(host: "127.0.0.1", port: PORT, timeout: TIMEOUT, client_info_tag: "")
      end
      assert_match(/client_info_tag must not be empty/, error.message)
    end

    def test_client_info_tag_rejects_whitespace_space
      error = assert_raises(ArgumentError) do
        Valkey.new(host: "127.0.0.1", port: PORT, timeout: TIMEOUT, client_info_tag: "has space")
      end
      assert_match(/client_info_tag must not contain whitespace/, error.message)
    end

    def test_client_info_tag_rejects_whitespace_tab
      error = assert_raises(ArgumentError) do
        Valkey.new(host: "127.0.0.1", port: PORT, timeout: TIMEOUT, client_info_tag: "has\ttab")
      end
      assert_match(/client_info_tag must not contain whitespace/, error.message)
    end

    def test_client_info_tag_rejects_whitespace_newline
      error = assert_raises(ArgumentError) do
        Valkey.new(host: "127.0.0.1", port: PORT, timeout: TIMEOUT, client_info_tag: "has\nnewline")
      end
      assert_match(/client_info_tag must not contain whitespace/, error.message)
    end

    # --- Core-side library-name validation (glide-core, upstream #6891) ---
    #
    # The Ruby wrapper deliberately does NOT re-implement library-name character
    # validation; glide-core validates the composed lib-name before client
    # creation and surfaces a configuration error through the FFI. These tests
    # assert that the error reaches the caller as a Valkey error at client
    # creation, rather than panicking or silently connecting with a name the
    # server ignores.
    #
    # Grammar enforced by core: printable ASCII \x21-\x27 and \x2A-\x7E (i.e.
    # excluding space, "(" and ")"), plus at most one matched, non-empty
    # trailing "(tag)". An empty value is treated as absent.
    CORE_REJECTED_LIB_NAMES = {
      "space" => "Glide Ruby",
      "tab" => "Glide\tRuby",
      "newline" => "Glide\nRuby",
      "non_ascii" => "café",
      "del_control_char" => "GlideRuby\x7F",
      "unclosed_paren" => "GlideRuby(",
      "empty_parens" => "GlideRuby()",
      "paren_only" => "(tag)",
      "double_tag" => "GlideRuby(tag)(second)",
      "trailing_suffix_after_tag" => "GlideRuby(tag)suffix"
    }.freeze

    CORE_REJECTED_LIB_NAMES.each do |label, value|
      define_method(:"test_core_rejects_lib_name_#{label}") do
        error = assert_raises(Valkey::BaseError) do
          client = Valkey.new(host: "127.0.0.1", port: PORT, timeout: TIMEOUT, lib_name: value)
          client.ping
        end
        assert_match(/library name must contain only printable ASCII/, error.message)
      end
    end

    def test_core_accepts_valid_composed_lib_name_and_tag
      client = Valkey.new(
        host: "127.0.0.1", port: PORT, timeout: TIMEOUT,
        lib_name: "custom-lib", client_info_tag: "framework:1.2"
      )
      client.close
    end

    def test_empty_lib_name_falls_back_to_default_without_error
      skip("lib_name tests only run on standalone mode") if cluster_mode?
      omit_version("7.2") # CLIENT SETINFO (lib-name) requires Valkey/Redis 7.2+

      client = _new_client(lib_name: "")
      begin
        info = client.call("CLIENT", "INFO")
        assert_match(/lib-name=GlideRuby/, info)
        refute_match(/lib-name=GlideRuby\(/, info)
      ensure
        client&.close
      end
    end

    # --- Integration tests (server needed) ---

    def test_client_info_tag_appends_to_default_lib_name
      skip("client_info_tag tests only run on standalone mode") if cluster_mode?
      omit_version("7.2") # CLIENT SETINFO (lib-name) requires Valkey/Redis 7.2+

      client = _new_client(client_info_tag: "my-framework:1.0")
      begin
        info = client.call("CLIENT", "INFO")
        assert_match(/lib-name=GlideRuby\(my-framework:1\.0\)/, info)
      ensure
        client&.close
      end
    end

    def test_lib_name_override
      skip("lib_name tests only run on standalone mode") if cluster_mode?
      omit_version("7.2") # CLIENT SETINFO (lib-name) requires Valkey/Redis 7.2+

      client = _new_client(lib_name: "CustomLib")
      begin
        info = client.call("CLIENT", "INFO")
        assert_match(/lib-name=CustomLib/, info)
      ensure
        client&.close
      end
    end

    def test_lib_name_with_client_info_tag
      skip("lib_name + client_info_tag tests only run on standalone mode") if cluster_mode?
      omit_version("7.2") # CLIENT SETINFO (lib-name) requires Valkey/Redis 7.2+

      client = _new_client(lib_name: "MyLib", client_info_tag: "v2.0")
      begin
        info = client.call("CLIENT", "INFO")
        assert_match(/lib-name=MyLib\(v2\.0\)/, info)
      ensure
        client&.close
      end
    end

    def test_default_lib_name_when_no_options
      skip("default lib_name tests only run on standalone mode") if cluster_mode?
      omit_version("7.2") # CLIENT SETINFO (lib-name) requires Valkey/Redis 7.2+

      client = _new_client
      begin
        info = client.call("CLIENT", "INFO")
        assert_match(/lib-name=GlideRuby/, info)
      ensure
        client&.close
      end
    end

    def test_client_info_tag_with_special_characters
      skip("client_info_tag tests only run on standalone mode") if cluster_mode?
      omit_version("7.2") # CLIENT SETINFO (lib-name) requires Valkey/Redis 7.2+

      client = _new_client(client_info_tag: "lmcache:1.2.3-beta+build.42")
      begin
        info = client.call("CLIENT", "INFO")
        assert_match(/lib-name=GlideRuby\(lmcache:1\.2\.3-beta\+build\.42\)/, info)
      ensure
        client&.close
      end
    end
  end
end
