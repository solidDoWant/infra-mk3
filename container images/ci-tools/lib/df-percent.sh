#!/bin/sh
# Prints the used percentage (a number, no % sign) of the filesystem in the
# `df -P` output on stdin. Uses only shell builtins, because it also runs in
# minimal images that lack awk, sed and grep.
set -eu
read -r _header
read -r _filesystem _blocks _used _available percent _mount
echo "${percent%\%}"
