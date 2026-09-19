#!/bin/sh
# Applies the keys from the Flux-managed server.ini onto the server's own INI on the data
# volume. Keys in the managed file win; every other line is left as the server wrote it,
# so settings changed in game are not reset on the next restart.
#
# A value of @NAME@ in the managed file is replaced with the environment variable NAME.
# That is how the join password gets in without being committed: hr.yaml wires it into
# this container from the project-zomboid-credentials Secret.
set -eu

source_ini=/etc/project-zomboid/server-config/server.ini
target_ini="$DATA_DIR/Server/$SERVER_NAME.ini"

mkdir -p "$DATA_DIR/Server"

# First start: the server has not written its INI yet. Merging into an empty file leaves
# just the managed keys, and the server fills in the rest with its defaults.
[ -f "$target_ini" ] || : > "$target_ini"

awk '
    function expand(line,   out, name) {
        # Consumes the line left to right, so a substituted value that happens to contain
        # @SOMETHING@ is not expanded again.
        out = ""
        while (match(line, /@[A-Z][A-Z0-9_]*@/)) {
            name = substr(line, RSTART + 1, RLENGTH - 2)
            out = out substr(line, 1, RSTART - 1) ENVIRON[name]
            line = substr(line, RSTART + RLENGTH)
        }
        return out line
    }
    NR == FNR {
        if ($0 ~ /^[A-Za-z][A-Za-z0-9_]*=/) {
            key = substr($0, 1, index($0, "=") - 1)
            managed[key] = expand($0)
            order[++count] = key
        }
        next
    }
    {
        if ($0 ~ /^[A-Za-z][A-Za-z0-9_]*=/) {
            key = substr($0, 1, index($0, "=") - 1)
            if (key in managed) {
                print managed[key]
                applied[key] = 1
                next
            }
        }
        print
    }
    END {
        # Managed keys the server has not written into its INI yet.
        for (i = 1; i <= count; i++) {
            if (!(order[i] in applied)) {
                print managed[order[i]]
            }
        }
    }
' "$source_ini" "$target_ini" > "$target_ini.new"

mv "$target_ini.new" "$target_ini"
