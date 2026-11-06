#!/usr/bin/env bash
# Wrapper around krr that port-forwards to vmselect for the duration of the run.
#
# krr's Prometheus auto-discovery goes through the apiserver service proxy but only
# forwards bearer tokens, not kubeconfig client certs, so it gets a 401 here
# (https://github.com/robusta-dev/krr/issues/300). This wrapper starts a
# port-forward on a random local port, passes it to krr with -p, and tears it
# down when krr exits.
#
# Runs the real binary directly (no port-forward) when -p/--prometheus-url is given,
# for help/version/completion, or when invoked by shell completion.

set -euo pipefail

KRR_BIN="${KRR_BIN:-/opt/krr/krr}"
PROM_NAMESPACE="${KRR_PROM_NAMESPACE:-monitoring}"
PROM_SERVICE="${KRR_PROM_SERVICE:-vmselect-victoria-metrics-k8s-stack}"
PROM_PORT="${KRR_PROM_PORT:-8481}"
PROM_PATH="${KRR_PROM_PATH:-/select/0/prometheus}"
FORWARD_TIMEOUT_SECONDS="${KRR_FORWARD_TIMEOUT_SECONDS:-20}"

# Shell completion calls the binary with _KRR_COMPLETE set; never port-forward on <TAB>.
if [[ -n "${_KRR_COMPLETE:-}" || $# -eq 0 || "$1" == "version" ]]; then
    exec "${KRR_BIN}" "$@"
fi

contexts=()
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
    case "${args[i]}" in
    -p | --prometheus-url | --prometheus-url=* | -h | --help | --install-completion | --show-completion)
        exec "${KRR_BIN}" "$@"
        ;;
    --all-clusters)
        echo "krr wrapper: --all-clusters isn't supported (one port-forward per run); pass -c <context> or -p <url>" >&2
        exit 2
        ;;
    -c | --context | --cluster)
        contexts+=("${args[i + 1]:-}")
        ;;
    --context=* | --cluster=*)
        contexts+=("${args[i]#*=}")
        ;;
    esac
done

if [[ ${#contexts[@]} -gt 1 ]]; then
    echo "krr wrapper: only one --context is supported per run; pass -p <url> to bypass the wrapper" >&2
    exit 2
fi

kubectl_args=()
if [[ ${#contexts[@]} -eq 1 ]]; then
    kubectl_args+=(--context "${contexts[0]}")
fi

forward_log="$(mktemp -t krr-port-forward.XXXXXX)"
forward_pid=""

cleanup() {
    if [[ -n "${forward_pid}" ]] && kill -0 "${forward_pid}" 2>/dev/null; then
        kill "${forward_pid}" 2>/dev/null || true
        wait "${forward_pid}" 2>/dev/null || true
    fi
    rm -f "${forward_log}"
}
trap cleanup EXIT

# Port 0 on the local side lets kubectl pick a free port; read it back from its output.
kubectl "${kubectl_args[@]}" -n "${PROM_NAMESPACE}" port-forward "svc/${PROM_SERVICE}" ":${PROM_PORT}" \
    >"${forward_log}" 2>&1 &
forward_pid=$!

local_port=""
deadline=$((SECONDS + FORWARD_TIMEOUT_SECONDS))
while [[ -z "${local_port}" ]]; do
    if ! kill -0 "${forward_pid}" 2>/dev/null; then
        echo "krr wrapper: port-forward to ${PROM_NAMESPACE}/svc/${PROM_SERVICE} exited:" >&2
        cat "${forward_log}" >&2
        exit 1
    fi
    if ((SECONDS >= deadline)); then
        echo "krr wrapper: timed out after ${FORWARD_TIMEOUT_SECONDS}s waiting for port-forward:" >&2
        cat "${forward_log}" >&2
        exit 1
    fi
    local_port="$(sed -nE 's/^Forwarding from 127\.0\.0\.1:([0-9]+) .*/\1/p' "${forward_log}" | head -n 1)"
    [[ -n "${local_port}" ]] || sleep 0.2
done

# Not exec'd: the EXIT trap has to run afterwards to stop the port-forward.
# On Ctrl-C, krr and kubectl both get SIGINT from the terminal and this script exits
# with them, still running the EXIT trap.
rc=0
"${KRR_BIN}" "$@" -p "http://127.0.0.1:${local_port}${PROM_PATH}" || rc=$?
exit "${rc}"
