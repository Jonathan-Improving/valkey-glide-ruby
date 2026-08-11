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

    # --- Integration tests (server needed) ---

    def test_client_info_tag_appends_to_default_lib_name
      skip("client_info_tag tests only run on standalone mode") if cluster_mode?

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
