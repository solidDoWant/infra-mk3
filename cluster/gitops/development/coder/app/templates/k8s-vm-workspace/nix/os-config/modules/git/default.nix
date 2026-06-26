{ ... }:
# System-wide git configuration (/etc/gitconfig), declarative replacement for the
# old configure-git.sh coder_script. These are all static, identity-independent
# usability/performance defaults - they are the same for every workspace, so they
# belong in the image rather than a per-start script. Per-user identity is still
# set at runtime (GIT_AUTHOR_* env + commit-signing module in configure-github.tf).
{
  programs.git = {
    enable = true;
    config = {
      core = {
        excludesfile = "/home/coder/.gitignore";
        # Filesystem monitor + untracked cache for performance in large repos.
        fsmonitor = true;
        untrackedCache = true;
      };
      column.ui = "auto";
      branch.sort = "-committerdate";
      tag.sort = "version:refname";
      diff = {
        algorithm = "histogram";
        colorMoved = "plain";
        mnemonicPrefix = true;
        renames = true;
      };
      push = {
        default = "simple";
        autoSetupRemote = true;
        followTags = true;
      };
      fetch = {
        prune = true;
        pruneTags = true;
        all = true;
      };
      help.autocorrect = "prompt";
      commit.verbose = true;
      rerere = {
        enabled = true;
        autoupdate = true;
      };
      rebase = {
        autoSquash = true;
        autoStash = true;
        updateRefs = true;
      };
      merge.conflictstyle = "zdiff3";
      pull.rebase = true;
    };
  };
}
