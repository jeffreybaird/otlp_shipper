# Codex PreToolUse timeout fix

[The patch](codex-0.153.4-pretool-fail-closed.patch) targets the official
[`rust-v0.153.4` source](https://github.com/openai/codex/tree/rust-v0.153.4),
commit `3d2ee51ca2d5db578f328aa75e20aa22c0197c9a`, matching the inspected
ChatGPT application's bundled Codex version. The source is Apache-2.0 licensed.

The command runner reports timeouts as execution errors. Previously the
PreToolUse parser reported those errors but left `should_block` false. This patch
sets a blocking reason for synchronous operational errors, including timeouts,
spawn failures and I/O failures. It preserves asynchronous hooks' advisory behavior
and keeps the failed hook's error visible. A separate successful hook cannot
rewrite the input to override that block.

Apply to an unmodified checkout of the exact source revision:

```sh
git apply --check /absolute/path/to/codex-0.153.4-pretool-fail-closed.patch
git apply /absolute/path/to/codex-0.153.4-pretool-fail-closed.patch
cd codex-rs
just fmt
just test -p codex-hooks
just fix -p codex-hooks
```

Validation on pinned Rust 1.95.0: the original error branch fails three of the four
new tests. The patched hook crate passes 179 tests, with zero skipped. Formatting
and scoped Clippy pass. Tests exercise real subprocess timeouts and startup
failure, partial output, competing input rewrites, and asynchronous behavior.

**This patch is not installed in the running application.** Applying it to source
does not replace the app's bundled executable or survive app updates. A reviewed
Codex build/release and a live host test are required before claiming that its
outer timeout is a hard stop. No signed application bundle was altered, and no
upstream issue or pull request was sent. This artifact changes timeout handling;
it does not turn untrusted/skipped hooks or arbitrary policy-classifier limitations
into guaranteed enforcement.
