{
  pkgs,
  config,
  lib,
  ...
}: {
  home.packages = with pkgs; [
    nil
    vscode
  ];

  # eventually we may want to move some config here, but for now
  # we rely on VSCode's own settings sync support.
  # programs.vscode = {
  #   enable = true;
  # {
  #   // * editor settings *
  #   "diffEditor.codeLens": true,
  #   "editor.codeActionsOnSave": {},
  #   "editor.cursorBlinking": "expand",
  #   "editor.cursorSmoothCaretAnimation": "off", // "on" | "off"
  #   "editor.defaultFormatter": "esbenp.prettier-vscode",
  #   "editor.detectIndentation": false,
  #   "editor.fontFamily": "'SauceCodePro Nerd Font', 'SauceCodeProNF', monospace",
  #   "editor.fontLigatures": false,
  #   "editor.fontSize": 15,
  #   "editor.formatOnSave": true,
  #   "editor.minimap.enabled": false,
  #   "editor.quickSuggestions": { "strings": true },
  #   "editor.smoothScrolling": true,
  #   "editor.tabSize": 2,
  #   "editor.unicodeHighlight.invisibleCharacters": false,
  #   "editor.wordWrapColumn": 500,

  #   // * file explorer settings *
  #   "files.exclude": {
  #     "**/*.meta": true
  #   },
  #   "explorer.compactFolders": false,

  #   // * formatter settings *
  #   "[javascript]": {
  #     "editor.defaultFormatter": "esbenp.prettier-vscode"
  #   },
  #   "[javascriptreact]": {
  #     "editor.defaultFormatter": "esbenp.prettier-vscode"
  #   },
  #   "[java]": {
  #     "editor.defaultFormatter": "mwpb.java-prettier-formatter"
  #   },
  #   "[html]": {
  #     "editor.defaultFormatter": "vscode.html-language-features"
  #   },
  #   "[prisma]": {
  #     "editor.defaultFormatter": "Prisma.prisma",
  #     "editor.formatOnSave": true
  #   },
  #   "[toml]": {},
  #   "[python]": {
  #     "editor.formatOnType": true
  #   },

  #   "nix.enableLanguageServer": true, // Enable LSP.
  #   "nix.serverPath": "nil", // The path to the LSP server executable.
  #   "nix.serverSettings": {
  #     "nil": {
  #       "formatting": { "command": ["nixpkgs-fmt"] }
  #     }
  #   },
  #   "[nix]": {
  #     "editor.defaultFormatter": "kamadorueda.alejandra",
  #     "editor.formatOnPaste": true,
  #     "editor.formatOnSave": true,
  #     "editor.formatOnType": false
  #   },

  #   // * prettier settings *
  #   "prettier.arrowParens": "always",
  #   "prettier.proseWrap": "never",
  #   "prettier.printWidth": 100,
  #   "prettier.trailingComma": "none",
  #   "prettier.bracketSameLine": true,
  #   "prettier.useEditorConfig": false,

  #   // * live Server settings *
  #   "liveServer.settings.donotVerifyTags": true,
  #   "liveServer.settings.donotShowInfoMsg": true,

  #   // * workbench settings *
  #   "workbench.iconTheme": "material-icon-theme",
  #   "workbench.list.smoothScrolling": true,
  #   "workbench.startupEditor": "none",

  #   // * terminal settings *
  #   "terminal.integrated.gpuAcceleration": "off",
  #   "terminal.integrated.defaultProfile.windows": "fish",
  #   "terminal.integrated.smoothScrolling": false,

  #   // * screencast settings *
  #   "screencastMode.fontSize": 48,
  #   "screencastMode.mouseIndicatorColor": "#00000000",

  #   // * miscellaneous settings *
  #   "cmake.configureOnOpen": false,
  #   "cmake.showOptionsMovedNotification": false,
  #   "explorer.confirmDragAndDrop": false,
  #   "go.toolsManagement.autoUpdate": true,
  #   "html.format.contentUnformatted": "",
  #   "javascript.updateImportsOnFileMove.enabled": "never",
  #   "npm.keybindingsChangedWarningShown": true,
  #   "redhat.telemetry.enabled": false,
  #   "settingsSync.ignoredSettings": [],
  #   "svg.preview.mode": "img",
  #   "terminal.external.osxExec": "Warp.app",
  #   "typescript.preferences.importModuleSpecifier": "non-relative",
  #   "vscode_vibrancy.opacity": 0.1,
  #   "window.titleBarStyle": "custom",
  #   "window.zoomLevel": 2,
  #   "workbench.statusBar.visible": false,
  # }
  # };
}
