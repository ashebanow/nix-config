{
  pkgs,
  lib,
  ...
}: {
  programs.vscode = {
    enable = true;
    enableUpdateCheck = false;
    enableExtensionUpdateCheck = false;
    mutableExtensionsDir = false;

    extensions = with pkgs.vscode-extensions;
      [
        aaron-bond.better-comments
        arrterian.nix-env-selector
        bradlc.vscode-tailwindcss
        catppuccin.catppuccin-vsc
        catppuccin.catppuccin-vsc-icons
        davidanson.vscode-markdownlint
        dbaeumer.vscode-eslint
        donjayamanne.githistory
        eamodio.gitlens
        ecmel.vscode-html-css
        editorconfig.editorconfig
        esbenp.prettier-vscode
        firefox-devtools.vscode-firefox-debug
        formulahendry.code-runner
        github.copilot
        github.vscode-github-actions
        github.vscode-pull-request-github
        golang.go
        jnoortheen.nix-ide
        kamadorueda.alejandra
        mikestead.dotenv
        ms-vscode-remote.remote-ssh
        oderwat.indent-rainbow
        redhat.java
        redhat.vscode-yaml
        rust-lang.rust-analyzer
        shopify.ruby-lsp
        streetsidesoftware.code-spell-checker
        stylelint.vscode-stylelint
        tailscale.vscode-tailscale
        tamasfe.even-better-toml
        unifiedjs.vscode-mdx
        usernamehw.errorlens
        yzhang.markdown-all-in-one
      ]
      ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
        # # TODO: add the following:
        # amodio.toggle-excluded-files
        # brpaz.vscode-obsidianmd
        # codeforge.remix-forge
        # csstools.postcss
        # ionutvmi.path-autocomplete
        # jackardios.vscode-css-to-tailwindcss
        # jeff-hykin.better-shellscript-syntax
        # jetpack-io.devbox
        # kdl-org.kdl
        # ms-playwright.playwright
        # ms-vscode-remote.vscode-remote-extensionpack
        # ms-vscode.remote-explorer
        # ms-vscode.remote-ssh-edit
        # ms-vscode.test-adapter-converter
        # ms-vsliveshare.vsliveshare
        # mtxr.sqltools
        # mtxr.sqltools-driver-pg
        # mtxr.sqltools-driver-sqlite
        # sleistner.vscode-fileutils
        # vitest.explorer
        {
          name = "path-autocomplete";
          publisher = "ionutvmi";
          version = "1.25.0";
          sha256 = "sha256-iz32o1znwKpbJSdrDYf+GDPC++uGvsCdUuGaQu6AWEo=";
        }
        {
          name = "kdl";
          publisher = "kdl-org";
          version = "1.3.1";
          sha256 = "sha256-0Wbyh6yaGyj/fyTUERB5KQd668i0fx/XLc/i2YkXYKg=";
        }
        {
          name = "vscode-fileutils";
          publisher = "sleistner";
          version = "3.10.3";
          sha256 = "sha256-v9oyoqqBcbFSOOyhPa4dUXjA2IVXlCTORs4nrFGSHzE=";
        }
        {
          name = "remote-ssh-edit";
          publisher = "ms-vscode-remote";
          version = "0.47.2";
          sha256 = "1hp6gjh4xp2m1xlm1jsdzxw9d8frkiidhph6nvl24d0h8z34w49g";
        }
      ];

    userSettings = {
      ## Appearances ##

      # the most important setting
      "editor.fontFamily" = lib.concatMapStringsSep ", " (s: "'${s}'") [
        "SauceCodePro Nerd Font"
      ];
      "editor.fontSize" = 12;
      "editor.cursorSmoothCaretAnimation" = "explicit";
      # "editor.cursorStyle" = "block";
      "editor.cursorBlinking" = "smooth";
      # "window.density.editorTabHeight" = "compact";

      "editor.accessibilitySupport" = "off";

      # popups are really annoying
      "editor.hover.delay" = 700;

      # colors
      "workbench.colorTheme" = "Catppuccin Mocha";
      # icons
      "workbench.iconTheme" = "Catppuccin Icons";

      # hide the default indentation guides to make way for the extension
      "editor.guides.indentation" = false;
      "indentRainbow.indicatorStyle" = "classic";

      # title
      "window.titleSeparator" = " - ";
      "window.title" = lib.concatMapStrings (s: "\${${s}}") [
        "rootName"
        "separator"
        "activeEditorMedium"
        "separator"
        "appName"
      ];

      # scale the ui down
      # "window.zoomLevel" = -1;
      # hide the menu bar unless alt is pressed
      "window.menuBarVisibility" = "toggle";
      # the minimap gets in the way
      "editor.minimap.enabled" = false;
      # scroll with an animation
      "editor.smoothScrolling" = true;
      "workbench.list.smoothScrolling" = true;

      "terminal.external.linuxExec" = "footclient";
      "terminal.external.osxExec" = "Warp.app";
      "terminal.integrated.smoothScrolling" = true;
      # set the integrated terminal to use zsh
      "terminal.integrated.defaultProfile.linux" = "zsh";
      # blink the cursor in terminal
      "terminal.integrated.cursorBlinking" = true;
      # line style cursor in terminal
      "terminal.integrated.cursorStyle" = "line";
      # fix fuzzy text in integrated terminal
      "terminal.integrated.gpuAcceleration" = "on";
      # this makes the terminal horribly slow, so disabled for now...
      # "terminal.integrated.shellIntegration.enabled" = true;

      # hide the action bar, I know the keybinds
      # "workbench.activityBar.location" = "hidden";
      # put the sidebar on the right so that text doesn't jump
      "workbench.sideBar.location" = "right";
      # no delay when automatically hiding the sidebar or panels

      # AutoHide does not cancel the timer if the panel is re-selected,
      # rendering these settings (and the extension) completely useless.
      # "autoHide.sideBarDelay" = 30000; # seconds
      # "autoHide.panelDelay" = 30000; # seconds

      # show vcs changes and staged changes as a tree
      "scm.defaultViewMode" = "tree";

      ## Saving and Formatting ##

      # auto-save when the active editor loses focus
      # "files.autoSave" = "onFocusChange";
      # format pasted code if the formatter supports a range
      "editor.formatOnPaste" = true;
      # if the plugin supports range formatting always use that
      # "editor.formatOnSaveMode" = "modificationsIfAvailable";
      # insert a newline at the end of a file when saved
      "files.insertFinalNewline" = true;
      # trim whitespace trailing at the ends of lines on save
      "files.trimTrailingWhitespace" = true;

      ## VCS Behavior ##

      # allow 6 more characters from default 50 in commit subject
      "git.inputValidationSubjectLength" = 56;

      # don't ask to confirm sync
      "git.confirmSync" = false;

      # prevent pollute history with whitespace changes
      "diffEditor.ignoreTrimWhitespace" = false;
      # show blames at the end of current line
      "gitblame.inlineMessageEnabled" = true;
      # blame message format for inline, remove "Blame"
      "gitblame.inlineMessageFormat" = "\${author.name} (\${time.ago})";
      "gitblame.inlineMessageNoCommit" = "Uncommitted changes";
      # blame message format for status bar
      "gitblame.statusBarMessageFormat" = "Blame \${author.name} (\${time.ago})";
      "gitblame.statusBarMessageNoCommit" = "Uncommitted changes";
      # open the changes in browser when clicking blame on status bar
      "gitblame.statusBarMessageClickAction" = "Open tool URL";

      ## Navigation Behavior ##

      # scrolling in tab bar switches
      "workbench.editor.scrollToSwitchTabs" = true;
      # name of current scope sticks to top of editor pane
      "editor.stickyScroll.enabled" = true;
      # larger indent
      "workbench.tree.indent" = 16;

      ## Intelligence Features ##

      # show the errors shortly after saving
      "errorLens.onSaveTimeout" = 200;
      # space between EOL and error
      "errorLens.margin" = "1em";
      # do not show error messages on lines in merge conflict blocks
      "errorLens.enabledInMergeConflict" = false;
      # diagnostic levels to show, removed "info"
      "errorLens.enabledDiagnosticLevels" = ["error" "warning"];
      # slower updates but less buggy
      "errorLens.delayMode" = "debounce";

      # don't add a trailing slash for dirs
      "path-autocomplete.enableFolderTrailingSlash" = false;

      ## Miscellaneous ##

      # don't re-open everything on start
      "window.restoreWindows" = "none";
      # don't show the welcome page
      "workbench.startupEditor" = "none";
      # unsaved files will be "untitled"
      "workbench.editor.untitled.labelFormat" = "name";
      # default hard and soft rulers
      "editor.rulers" = [80 120];
      # files can be recovered with undo
      "explorer.confirmDelete" = false;
      # never ask to open parent git repo if one-off
      "git.openRepositoryInParentFolders" = "never";
    };

    keybindings = let
      formatOnManualSaveOnlyCondition = lib.concatStringsSep " " [
        # manually saving should only format when auto-saving is enabled
        # in some form, and when the file doesn't already
        # get formatted on every save
        "config.editor.autoSave != off"
        "&& !config.editor.formatOnSave"
        # any other clauses match the default
        # ctrl+k ctrl+f manual format command
        "&& editorHasDocumentFormattingProvider"
        "&& editorTextFocus"
        "&& !editorReadonly"
        "&& !inCompositeEditor"
      ];
    in [
      # ### FORMAT DOCUMENT ON MANUAL SAVE ONLY ###

      # # remove the default action for saving document
      # {
      #   key = "ctrl+s";
      #   command = "-workbench.action.files.save";
      #   when = formatOnManualSaveOnlyCondition;
      # }
      # # formatting behavior identical to the default ctrl+k ctrl+f
      # # and the save as normal
      # {
      #   key = "ctrl+s";
      #   command = "extension.multiCommand.execute";
      #   args = {
      #     sequence = ["editor.action.formatDocument" "workbench.action.files.save"];
      #   };
      #   when = formatOnManualSaveOnlyCondition;
      # }

      # ### END ###

      ### DELETE CURRENT LINE ###

      {
        key = "ctrl+d";
        command = "editor.action.deleteLines";
        when = "textInputFocus && !editorReadonly";
      }

      ### END ###

      ### INSERT TAB CHARACTER ###

      {
        key = "ctrl+k tab";
        command = "type";
        args = {text = "	";};
        when = "editorTextFocus && !editorReadonly";
      }

      ### END ###

      ### FOCUS THE TERMINAL ###

      # {
      #   key = "shift+`";
      #   command = "workbench.action.terminal.focus";
      # }

      ### END ###

      ### FOCUS ON FILE EXPLORER SIDEBAR ###

      {
        key = "ctrl+e";
        command = "-workbench.action.quickOpen";
      }
      {
        key = "ctrl+e";
        command = "workbench.files.action.focusFilesExplorer";
      }

      ### END ###
    ];
  };
}
