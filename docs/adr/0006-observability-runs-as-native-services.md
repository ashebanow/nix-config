# The observability stack runs as native NixOS services, not containers

Status: accepted (2026-11-23, BOX-317)

ADR 0002 moves container workloads to Quadlet, so a reader would expect new services to arrive as
containers. The observability stack deliberately does not. VictoriaMetrics, VictoriaLogs, vmalert,
Alertmanager, Grafana and the per-machine agents (node_exporter, vmagent,
`systemd-journal-upload`) all have nixpkgs modules with NixOS tests, and their configuration,
scrape targets, alert rules and Grafana provisioning are expressible as Nix values that
`nix flake check` validates. Containers would add pinned images and a second update path beside
nixpkgs bumps, which works against the effort's first criterion: low ongoing maintenance.

ADR 0002's goal was declarativeness, not containers for their own sake; native modules meet that
goal more directly. The Quadlet decision still governs workloads that only ship as images (the
model server, bifrost, Open WebUI, the memory stack).
