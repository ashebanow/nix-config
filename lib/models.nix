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
    "bartowski/Qwen_Qwen3.6-27B-GGUF:Q4_K_M" = {
      file = "Qwen_Qwen3.6-27B-Q4_K_M.gguf";
      url = "https://huggingface.co/bartowski/Qwen_Qwen3.6-27B-GGUF/resolve/main/Qwen_Qwen3.6-27B-Q4_K_M.gguf";
      # Fill in after first download:
      # sha256 = "sha256-...";
    };
  };

  # Model metadata — used when model is not yet promoted to ggufs.
  # llama.cpp downloads on demand via -hf flag.
  models = {
    qwen3-27b = {
      hf = "bartowski/Qwen_Qwen3.6-27B-GGUF:Q4_K_M";
      ctxSize = 32768;
      flashAttn = true;
      ngl = 999;
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
