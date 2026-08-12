# Changelog

## Pending

### Breaking Changes

* Ruby: `client` dispatcher uses `public_send` instead of `send` — subclasses that previously relied on dispatching to private `client_*` helpers via the `client(:subcommand)` interface must make those methods public. This prevents accidental invocation of unrelated private methods and aligns with Ruby best practices. ([PR #1](https://github.com/Jonathan-Improving/valkey-glide-ruby/pull/1))

### Changes

* Ruby: Add Alpine Linux (musl libc) support for x86_64 and aarch64 — runtime detection of musl libc, CI/CD pipeline for native builds, and prebuilt `libglide_ffi.so` for musl targets ([#143](https://github.com/valkey-io/valkey-glide-ruby/pull/143))
* Ruby: Add distributed tracing support — `Valkey::OpenTelemetry.set_parent_span_context_provider` (and `init(parent_span_context_provider:)`) let an app propagate its current W3C trace context into command/pipeline spans, so they become children of the app's trace instead of independent root spans, matching the Node.js client's `parentSpanContextProvider` behavior.
