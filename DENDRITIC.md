# The Dendritic Pattern

A [Nixpkgs module system](https://nix.dev/tutorials/module-system/) usage pattern for organizing Nix configurations.

## Core Idea

The Dendritic pattern reconciles the complexity of modern Nix configurations—multiple systems (NixOS, nix-darwin, home-manager), sharing across machines, and cross-cutting concerns—using the Nixpkgs module system at a "top-level" configuration (often flake-parts).

Every Nix file (except entry points like `flake.nix`) is a module of this top-level configuration. Each module:

- Implements a single feature
- ...across all applicable configuration classes (nixos, darwin, home-manager, etc.)
- Lives at a path that names that feature

## The Problem It Solves

Before dendritic tools, Nix configurations were written with host-specific and user-specific details baked in. Evaluating a module often required downloading all of an author's particular inputs. The Nix community developed a copy-paste culture because there was no mechanism for sharing composable configuration units.

The Dendritic ecosystem makes configurations **re-usable** by treating them as parametric functions, not static configurations.

## Key Libraries

- **flake-aspects**: Zero-dependency foundation for composing aspects—transposition, dependency DAGs, parametric providers, nestable sub-aspects
- **den**: Context-aware configuration framework with declarative pipelines, host/user schemas, and batteries included
- **dendrix**: Community-driven distribution index of dendritic aspects
- **import-tree**: Recursively import Nix modules from a directory tree
- **flake-file**: Define flake inputs as typed Nix module options

## Design Principles

- **Composable**: Small, focused functions that combine naturally
- **No lock-in**: Works with or without flakes, flake-parts, etc.
- **Dependency-minimal**: Most libraries have zero or near-zero external dependencies
- **Well-tested**: CI with checkmate, extensive test suites

## Checklist

### Do

- **Do** implement each module for a single feature or concern
- **Do** make modules parametric (accept options) rather than hardcoding values
- **Do** place modules at paths that reflect their feature name
- **Do** support multiple configuration classes (nixos, darwin, home-manager) in each module
- **Do** use options to declare dependencies between modules
- **Do** keep modules focused—extract sub-concerns into separate modules
- **Do** write tests for your modules using `checkmate` or similar
- **Do** document module options with descriptions

### Don't

- **Don't** bake host-specific or user-specific values directly into modules
- **Don't** create modules that depend on external inputs unrelated to their feature
- **Don't** make modules that are too broad (e.g., "my entire config")
- **Don't** create implicit dependencies—use explicit option declarations
- **Don't** duplicate functionality across modules
- **Don't** use modules as simple include files—treat them as composable functions

## See Also

- [Original dendritic pattern](https://github.com/mightyiam/dendritic) by @mightyiam
- [den](https://github.com/denful/den) by @vic
- [Dendritic ecosystem overview](https://denful.dev/ecosystem/overview/)
- [Why Dendritic?](https://denful.dev/motivation/)
- [Aspect-oriented dendritic](https://github.com/denful/den) (den framework)
