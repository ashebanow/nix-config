# Model catalog — adapted from Doug Campos' approach to declarative model management.
# https://random.qmx.me/posts/2026/01/08/nixifying-local-llms/
# https://github.com/qmx/dotfiles/blob/master/lib/models.nix
#
# Two tiers:
#   1. ggufs: SHA256-verified models fetched via Nix (content-addressed, cached)
#   2. models: metadata-only — llama.cpp downloads on demand via -hf flag
#
# Promotion workflow (from QMX blog):
#   1. Add model to `models` section → experiment with -hf flag
#   2. Once satisfied, compute SHA256 on lumquat:
#        nix-hash --flat --type sha256 /path/to/model.gguf | nix-to-sri
#   3. Fill in sha256 below → model becomes a Nix derivation
#   4. All machines share from Nix cache at LAN speed
{ lib, ... }:
let
  inherit (lib) optionalString;
in
rec {
  # Promoted models with SHA256 hashes — fetched via pkgs.fetchurl.
  # Nix verifies integrity and caches the result.
  #
  # Qwen3.8-27B is currently unpromoted (experimental -hf path); once stable,
  # compute the SHA256 on lumquat and add it here (see promotion workflow in
  # the header comment).
  ggufs = { };

  # Model metadata — used when model is not yet promoted to ggufs.
  # llama.cpp downloads on demand via -hf flag.
  models = {
    # Coding assistant — Qwen 3.8 27B (dense), UD-Q8_K_XL, 4 slots × 256K, MTP.
    # Sampling follows the Qwen3.8 recommended THINKING-mode settings
    # (https://unsloth.ai/docs/models/qwen3.8 + HF README): temperature=1.0,
    # top_p=0.95, top_k=20, min_p=0.0, presence_penalty=0.0,
    # repetition_penalty=1.0 (llama.cpp default — not passed).
    # MTP is trained into the model (HF README: "MTP (Multi-Token Prediction):
    # trained with multiple steps") — no -MTP variant needed.
    # 8-bit UD-Q8_K_XL ≈ 31 GB weights (unsloth hardware table);
    # 1M total context at q4_0 KV fits in ~124 GB VRAM.
    qwen-35b-a3b = {
      hf = "unsloth/Qwen3.8-27B-GGUF:UD-Q8_K_XL";
      ctxSize = 1048576; # 4 slots × 256K (total context pool; 256K native per request)
      flashAttn = true;
      ngl = 999;
      port = 8080;
      # Host-side loopback port its llama-server `/metrics` is published on.
      # Documented in full under "The `metricsPort` field" below.
      metricsPort = 8081;
      primary = true; # target for the generic /llm serve path
      extraFlags = [
        "-np"
        "4" # Parallel slots — 256K each, 1M total pool
        "--jinja" # Jinja template engine (chat template)
        "--spec-type"
        "draft-mtp" # MTP speculative decoding (built-in MTP heads)
        "--spec-draft-n-max"
        "2" # Draft 2 tokens per step (matches unsloth vLLM example)
        "--cache-type-k"
        "q4_0" # Q4 KV cache (~4x reduction vs F16)
        "--cache-type-v"
        "q4_0"
        "--temp"
        "1.0" # Qwen3.8 thinking-mode recommendation
        "--top-p"
        "0.95" # Qwen3.8 thinking-mode recommendation
        "--top-k"
        "20" # Qwen3.8 thinking-mode recommendation
        "--min-p"
        "0.0" # Qwen3.8 thinking-mode recommendation
        "--presence-penalty"
        "0.0" # Qwen3.8 thinking-mode recommendation
        "--reasoning-effort"
        "medium" # Balance accuracy vs speed (unsloth example)
      ];
    };
  };

  # ── The `metricsPort` field ─────────────────────────────────────────
  #
  # Every model entry may declare `metricsPort`: the **host** TCP port that
  # model's llama-server `/metrics` endpoint is published on, bound to 127.0.0.1.
  # `modules/features/llm.nix` publishes it (`127.0.0.1:<metricsPort>:8080`, note
  # the container-internal side is always 8080 because that is `--port`), and the
  # same module declares `my.observability.scrapeTargets.llama-<name>` from it, so
  # adding a model to this catalog gets its metrics collected with no other edit.
  #
  # Why a *separate* published port rather than scraping the inference port: the
  # inference port is deliberately not published on lumquat (models are reachable
  # only through the bifrost gateway on the `llm-internal` bridge, BOX-138).
  # Publishing 8080 to expose metrics would re-open that door; a dedicated
  # loopback-only port exposes the metrics endpoint and nothing else. It is the
  # same HTTP listener — llama.cpp serves `/metrics` next to `/v1/*` — so the door
  # is loopback-bound and this host's vmagent is the only client.
  #
  # The field is optional. A model without it publishes no metrics port and gets
  # no scrape target; that is the honest state for a model whose metrics nobody
  # has decided to collect, not an error.

  # Fetch a model file via Nix (if promoted) or return null (use -hf fallback).
  # Adapted from qmx/dotfiles modules/home-manager/llama-swap/default.nix
  fetchModel =
    {
      pkgs,
      hfRef,
    }:
    let
      gguf = ggufs.${hfRef} or null;
    in
    if gguf != null && gguf ? sha256 then
      pkgs.fetchurl {
        inherit (gguf) url sha256;
      }
    else
      null;
}
