# Model Catalog

Adapted from [Doug Campos' approach](https://random.qmx.me/posts/2026/01/08/nixifying-local-llms/)
([qmx/dotfiles](https://github.com/qmx/dotfiles/blob/master/lib/models.nix)).

## Two-Tier System

| Tier | `lib/models.nix` section | Mechanism | When to use |
|------|--------------------------|-----------|-------------|
| Experimental | `models` | `-hf` flag → llama.cpp downloads from HuggingFace | Trying new models, initial deploy |
| Promoted | `ggufs` | `pkgs.fetchurl` with SHA256 → Nix store path | Daily drivers, verified models |

## Promotion Workflow

1. Add model to `models` section → deploy with `-hf` flag
2. Model downloads on first request to llama.cpp server
3. Find the downloaded file:
   ```bash
   # llama.cpp HF cache
   find /var/lib/llm-models -name "*.gguf"
   ```
4. Compute SHA256:
   ```bash
   nix-hash --flat --type sha256 /path/to/model.gguf | nix-to-sri
   ```
5. Add to `ggufs` section in `lib/models.nix`:
   ```nix
   ggufs = {
     "org/model:quant" = {
       file = "model-name.gguf";
       url = "https://huggingface.co/org/model/resolve/main/model-name.gguf";
       sha256 = "sha256-...";   # ← fill in from step 4
     };
   };
   ```
6. Rebuild: model is now a content-addressed Nix derivation

## Benefits After Promotion

- **Integrity**: SHA256 verified on every build
- **Caching**: Shared across machines via Nix cache
- **Speed**: LAN cache instead of HuggingFace download
- **Reproducibility**: Exact model version tracked in git

## How llm.nix Uses the Catalog

```nix
model = modelsLib.fetchModel { inherit pkgs; hfRef = "org/model:quant"; };

# If promoted → Nix store path
#   volumes = ["${model}:/models/file.gguf:ro"];
#   cmd = ["llama-server" "-m" "${model}" ...];

# If experimental → HF download on demand
#   volumes = ["/var/lib/llm-models:/root/.cache/llama.cpp"];
#   cmd = ["llama-server" "-hf" "org/model:quant" ...];
```

The `modelArg` and `modelVolumes` variables switch automatically based on
whether the SHA256 is filled in.
