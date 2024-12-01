#!/bin/bash

set -euo pipefail
shopt -s extglob

# Get the SQL service name from one of the pods
JQ_QUERY="$(cat <<EOF
.items | first |
.spec.containers | map(select(.name == "server" or .name == "worker")) | first |
.env | map(select(.name == "AUTHENTIK_POSTGRESQL__HOST")) | first |
.value | split(".") | first | gsub("-r[wo]?$"; "")
EOF
)"
SQL_CLUSTER_NAME="$(
    kubectl get pod -n security -l 'app.kubernetes.io/name=authentik' -o json | jq -r "${JQ_QUERY}"
)"

# Get a list of errors
# cspell:words systemtask psql
SQL_QUERY="select jsonb_agg(j) from (select name,uid,description,task_call_module,messages from authentik_events_systemtask where status = 'error') j;"
ERRORS="$(kubectl cnpg psql -n security "${SQL_CLUSTER_NAME}" -t=false -i=false -- 'authentik' -t -c "${SQL_QUERY}")"
# Trim leading and trailing whitespace
ERRORS="${ERRORS##+([[:space:]])}"
ERRORS="${ERRORS%%+([[:space:]])}"

if [[ -z "${ERRORS}" ]]; then
    echo "No errors found"
    exit
fi

# Log the errors
echo "Found $(echo "${ERRORS}" | jq -c 'length // 0') errors"
echo "${ERRORS}" | jq -c '.[]' | while read -r error ; do
    echo "Task: $(echo "${error}" | jq -r '.name + "." + .task_call_module + "/" + .uid + ": " + .description')"
    echo 'Errors:'
    echo "${error}" | jq '.messages[]'
done
