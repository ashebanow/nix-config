{self, ...}: {
  flake.nixosModules.llm_serve = {
    pkgs,
    config,
    ...
  }: {
    users.users.llm_serve = {
      isSystemUser = true;
      description = "LLM serving user";
      group = "llm_serve";
    };

    users.groups.llm_serve = {};
  };
}