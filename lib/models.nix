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
{lib, ...}: let
  inherit (lib) optionalString;
in rec {
  # Promoted models with SHA256 hashes — fetched via pkgs.fetchurl.
  # Nix verifies integrity and caches the result.
  ggufs = {
    # Promoted — downloaded via Nix (SHA256 verified).
    "unsloth/Qwen3.6-35B-A3B-MTP-GGUF:UD-Q8_K_XL" = {
      file = "Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf";
      url = "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF/resolve/main/Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf";
      sha256 = "sha256-bGuBZTerrZCyUKCXKzRUZgKNhh3f4xbV8N4xymRA94E=";
    };
  };

  # Model metadata — used when model is not yet promoted to ggufs.
  # llama.cpp downloads on demand via -hf flag.
  models = {
    # Coding assistant — Qwen 3.6 35B MoE (3B active), UD-Q8_K_XL, 256K ctx, MTP
    # NOTE: UD-Q8_K_XL is the highest quant available for MTP; fits comfortably in 104 GB alone
    qwen-35b-a3b = {
      hf = "unsloth/Qwen3.6-35B-A3B-MTP-GGUF:UD-Q8_K_XL";
      ctxSize = 1572864; # 6 slots × 256K (total context pool)
      flashAttn = true;
      ngl = 999;
      port = 8080;
      extraFlags = [
        "-np"
        "6" # Parallel slots — 2 users × ~3 subagents, ~23-35 GB GTT headroom
        "--jinja" # Jinja template support
        "--spec-type"
        "draft-mtp" # Multi-Token Prediction (~2x faster)
        "--spec-draft-n-max"
        "3" # Draft 3 tokens per step
        "--cache-type-k"
        "q4_0" # Q4 KV cache (~4x reduction vs F16, negligible quality loss)
        "--cache-type-v"
        "q4_0"
        "--embeddings" # Enable /embedding endpoint for Honcho semantic search
      ];
    };
  };

  # Fetch a model file via Nix (if promoted) or return null (use -hf fallback).
  # Adapted from qmx/dotfiles modules/home-manager/llama-swap/default.nix
  fetchModel = {
    pkgs,
    hfRef,
  }: let
    gguf = ggufs.${hfRef} or null;
  in
    if gguf != null && gguf ? sha256
    then
      pkgs.fetchurl {
        inherit (gguf) url sha256;
      }
    else null;
}
