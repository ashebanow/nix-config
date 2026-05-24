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
{
  lib,
  ...
}: let
  inherit (lib) optionalString;
in rec {
  # Promoted models with SHA256 hashes — fetched via pkgs.fetchurl.
  # Nix verifies integrity and caches the result.
  ggufs = {
    # TODO: Fill in SHA256 after first deployment.
    # Model will be downloaded via -hf flag until hash is known.
    "unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q8_K_XL" = {
      file = "Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf";
      url = "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/main/Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf";
      # Fill in after first download:
      # sha256 = "sha256-...";
    };

    "unsloth/gemma-3-27b-it-GGUF:UD-Q8_K_XL" = {
      file = "gemma-3-27b-it-UD-Q8_K_XL.gguf";
      url = "https://huggingface.co/unsloth/gemma-3-27b-it-GGUF/resolve/main/gemma-3-27b-it-UD-Q8_K_XL.gguf";
      # Fill in after first download:
      # sha256 = "sha256-...";
    };
  };

  # Model metadata — used when model is not yet promoted to ggufs.
  # llama.cpp downloads on demand via -hf flag.
  models = {
    # Coding assistant — Qwen 3.6 35B MoE (3B active), Q8, 128K ctx, MTP
    qwen-35b-a3b = {
      hf = "unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q8_K_XL";
      ctxSize = 131072; # 128K
      flashAttn = true;
      ngl = 999;
      port = 8080;
      extraFlags = [
        "--jinja" # Jinja template support
      ];
    };

    # Creative/multimodal — Gemma 3 27B, Q8, 256K ctx
    gemma-27b = {
      hf = "unsloth/gemma-3-27b-it-GGUF:UD-Q8_K_XL";
      ctxSize = 262144; # 256K
      flashAttn = true;
      ngl = 999;
      port = 8081;
      extraFlags = [
        "--cache-type-k" "q4_0" # Q4 KV cache to save memory
        "--cache-type-v" "q4_0"
      ];
    };
  };

  # Fetch a model file via Nix (if promoted) or return null (use -hf fallback).
  # Adapted from qmx/dotfiles modules/home-manager/llama-swap/default.nix
  fetchModel = {pkgs, hfRef}:
    let
      gguf = ggufs.${hfRef} or null;
    in
      if gguf != null && gguf ? sha256
      then pkgs.fetchurl {
        inherit (gguf) url sha256;
      }
      else null;
}
