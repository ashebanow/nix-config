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

    "unsloth/gemma-3-27b-it-GGUF:UD-Q5_K_XL" = {
      file = "gemma-3-27b-it-UD-Q5_K_XL.gguf";
      url = "https://huggingface.co/unsloth/gemma-3-27b-it-GGUF/resolve/main/gemma-3-27b-it-UD-Q5_K_XL.gguf";
      # Fill in after first download:
      # sha256 = "sha256-...";
    };
  };

  # Model metadata — used when model is not yet promoted to ggufs.
  # llama.cpp downloads on demand via -hf flag.
  models = {
    # Coding assistant — Qwen 3.6 35B MoE (3B active), UD-Q8_K_XL, 128K ctx, MTP
    # NOTE: UD-Q8_K_XL is the highest quant available for MTP; fits comfortably in 104 GB alone
    qwen-35b-a3b = {
      hf = "unsloth/Qwen3.6-35B-A3B-MTP-GGUF:UD-Q8_K_XL";
      ctxSize = 131072; # 128K
      flashAttn = true;
      ngl = 999;
      port = 8080;
      extraFlags = [
        "--jinja" # Jinja template support
        "--spec-type"
        "draft-mtp" # Multi-Token Prediction (~2x faster)
        "--spec-draft-n-max"
        "3" # Draft 3 tokens per step
        "--cache-type-k"
        "q4_0" # Q4 KV cache (~4x reduction vs F16, negligible quality loss)
        "--cache-type-v"
        "q4_0"
      ];
    };

    # Creative/multimodal — Gemma 3 27B, Q5_K_XL
    # NOTE: The GGUF's n_ctx_train is 131072, so 256K requests get capped to 128K.
    #       Set to 128K explicitly to avoid the useless over-reservation.
    # NOTE: Gemma 3 does NOT support MTP (no MTP heads in architecture).
    #       Only Qwen 3.x models have graftable MTP layers.
    gemma-27b = {
      hf = "unsloth/gemma-3-27b-it-GGUF:UD-Q5_K_XL";
      ctxSize = 131072; # 128K (actual train ctx; 256K was being silently capped)
      flashAttn = true;
      ngl = 999; # ROCm allocates full model buffer regardless of ngl; ngl just controls compute
      port = 8081;
      extraFlags = [
        "--cache-type-k"
        "q4_0" # Q4 KV cache to save memory
        "--cache-type-v"
        "q4_0"

        # Speculative decoding: Gemma 3 1B drafts tokens for 27B (~2x speedup)
        # (2B is gated on HF, 1B is public and shares the same tokenizer)
        "--spec-draft-hf"
        "unsloth/gemma-3-1b-it-GGUF:Q8_0"
        "--spec-draft-n-max"
        "8" # Draft 8 tokens per step
        "--spec-draft-p-min"
        "0.6" # Accept ~60%+ probability matches

        # Performance tuning
        "--threads"
        "32" # Use all 32 logical threads (16C/32T)
        "--threads-batch"
        "32"
        "--poll"
        "100" # Max polling = lower latency on unified memory
        "--prio"
        "2" # High process priority
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
