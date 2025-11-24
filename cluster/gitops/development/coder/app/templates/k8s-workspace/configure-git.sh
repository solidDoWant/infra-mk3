#!/usr/bin/env bash

set -euo pipefail

# Set up general sudo git configuration options for better usability and performance.
# cspell:words committerdate conflictstyle excludesfile fsmonitor rerere zdiff3
# shellcheck disable=SC2016
sudo git config set --system --comment 'Set file "${DEFAULT_GITCONFIG_PATH}" gitignore file.' core.excludesfile ~/.gitignore
sudo git config set --system --comment 'Enable automatic column formatting in git output.' column.ui auto
sudo git config set --system --comment 'Sort branches by the date of the last commit.' branch.sort -committerdate
sudo git config set --system --comment 'Sort tags by version.' tag.sort version:refname
sudo git config set --system --comment 'Use the histogram algorithm for diffs.' diff.algorithm histogram
sudo git config set --system --comment 'Use plain color for moved lines in diffs.' diff.colorMoved plain
sudo git config set --system --comment 'Use mnemonic prefixes in diffs.' diff.mnemonicPrefix true
sudo git config set --system --comment 'Detect renames in diffs.' diff.renames true
sudo git config set --system --comment 'Use simple push behavior.' push.default simple
sudo git config set --system --comment 'Automatically set up remote tracking branches on push.' push.autoSetupRemote true
sudo git config set --system --comment 'Push tags along with commits.' push.followTags true
sudo git config set --system --comment 'Automatically prune remote-tracking branches during fetch.' fetch.prune true
sudo git config set --system --comment 'Automatically prune tags during fetch.' fetch.pruneTags true
sudo git config set --system --comment 'Fetch all remotes.' fetch.all true
sudo git config set --system --comment 'Enable autocorrect for git commands with a prompt.' help.autocorrect prompt
sudo git config set --system --comment 'Show diff of changes in commit messages.' commit.verbose true
sudo git config set --system --comment 'Enable reuse of recorded resolution for conflicted merges.' rerere.enabled true
sudo git config set --system --comment 'Automatically update recorded resolutions.' rerere.autoupdate true
sudo git config set --system --comment 'Automatically squash commits during rebase.' rebase.autoSquash true
sudo git config set --system --comment 'Automatically stash changes before rebasing.' rebase.autoStash true
sudo git config set --system --comment 'Update refs after rebasing.' rebase.updateRefs true
sudo git config set --system --comment 'Enable filesystem monitoring for better performance.' core.fsmonitor true
sudo git config set --system --comment 'Enable untracked cache for better performance.' core.untrackedCache true
sudo git config set --system --comment "Use 'zdiff3' style for merge conflicts." merge.conflictstyle zdiff3
sudo git config set --system --comment 'Use rebase instead of merge when pulling changes.' pull.rebase true
