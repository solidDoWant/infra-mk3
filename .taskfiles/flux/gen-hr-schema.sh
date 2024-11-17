#!/bin/bash
set -e
shopt -s extdebug

fatal() {
    [[ -z "${1}" ]] || >&2 echo "${@}"
    exit 1
}

get_helm_file_path() {
    # Use the arg-provided path if provided
    if [[ -n "${BASH_ARGV[1]}" ]]; then
        echo "${BASH_ARGV[1]}"
        return
    fi

    # Find the first file in the current directory with `kind: HelmRelease`
    shopt -s nullglob
    for yaml_file in {*.yaml,*.yml}; do
        if yq -e '.kind == "HelmRelease"' "${yaml_file}" > /dev/null 2> /dev/null; then
            >&2 echo "Found HelmRelease at ${yaml_file}"
            echo "${yaml_file}"
            return
        fi
    done

    # Fail
    fatal "No helm release found, please provide path via CLI arg"
}

get_artifact_hub_schema_url() {
    PACKAGE_PATH="${1}"
    [[ -n "${PACKAGE_PATH}" ]] || fatal '(bug) Package path not set'

    >&2 echo "Checking artifact hub for '${PACKAGE_PATH}'..."
    if ! API_RESPONSE="$(curl -fsSL -H 'accept: application/json' "https://artifacthub.io/api/v1/packages/helm/${PACKAGE_PATH}")"; then
        >&2 echo "No matching package found"
        return
    fi

    if echo "${API_RESPONSE}" | jq -e '.has_values_schema | not' > /dev/null; then
        >&2 echo "Package found, but does not have a values schema available"
        return
    fi

    LATEST_VERSION="$(echo "${API_RESPONSE}" | jq -r '.version')"
    CHART_VERSION="${2:-${LATEST_VERSION}}"
    if ! echo "${API_RESPONSE}" | jq -e --arg CHART_VERSION "${CHART_VERSION}" '.available_versions[] | select(.version == $CHART_VERSION)' > /dev/null; then
        >&2 echo "Package and value schema found, but no schema available for ${CHART_VERSION}"
        return
    fi

    >&2 echo 'Schema found'

    PACKAGE_ID="$(echo "${API_RESPONSE}" | jq -r '.package_id')"

    echo "https://artifacthub.io/api/v1/packages/${PACKAGE_ID}/${CHART_VERSION}/values-schema"
}

get_chart_url() {
    # Use the arg-provided value if there is one
    if [[ -n "${BASH_ARGV[0]}" ]]; then
        echo "${BASH_ARGV[0]}"
        return
    fi

    CHART_NAME="$(yq '.spec.chart.spec.chart' "${HELM_FILE_PATH}")"
    [[ -n "${CHART_NAME}" ]] || (>&2 echo 'Chart name not set'; exit 1)
    CHART_SOURCE_NAME="$(yq '.spec.chart.spec.sourceRef.name' "${HELM_FILE_PATH}")"
    [[ -n "${CHART_SOURCE_NAME}" ]] || (>&2 echo 'Chart source name not set'; exit 1)
    CHART_VERSION="$(yq '.spec.chart.spec.version' "${HELM_FILE_PATH}")"
    [[ -n "${CHART_VERSION}" ]] || (>&2 echo 'Chart version not set'; exit 1)


    # Look on artifact hub for <chart repo name>/<chart name>
    ARTIFACT_HUB_URL="$(get_artifact_hub_schema_url "${CHART_SOURCE_NAME%%-charts}/${CHART_NAME}")"
    if [[ -n "${ARTIFACT_HUB_URL}" ]]; then
        echo "${ARTIFACT_HUB_URL}"
        return
    fi

    # Look on artifact hub for <chart name>/<chart name>
    ARTIFACT_HUB_URL="$(get_artifact_hub_schema_url "${CHART_NAME}/${CHART_NAME}")"
    if [[ -n "${ARTIFACT_HUB_URL}" ]]; then
        echo "${ARTIFACT_HUB_URL}"
        return
    fi

    # Fail
    fatal "No chart found, please provide URL via CLI arg"
}

HELM_FILE_PATH="$(get_helm_file_path)"

# Validation
yq '.kind' "${HELM_FILE_PATH}" > /dev/null || fatal "File at '${HELM_FILE_PATH}' is not a HelmRelease"

# Get the schema URL
SCHEMA_URL="$(get_chart_url)"

# Build the HR schema URL
HELM_RELEASE_API_VERSION="$(yq '.apiVersion' "${HELM_FILE_PATH}")"
HELM_RELEASE_GROUP="${HELM_RELEASE_API_VERSION%%/*}"
HELM_RELEASE_VERSION="${HELM_RELEASE_API_VERSION##*/}"
HELM_RELEASE_SCHEMA_URL="https://kubernetes-schemas.pages.dev/$(echo "${HELM_RELEASE_GROUP}" | tr '[:upper:]' '[:lower:]')/helmrelease_$(echo "${HELM_RELEASE_VERSION}" | tr '[:upper:]' '[:lower:]').json"

# Download the helm release schema and set the ref
SCHEMA_PATH="$(dirname "${HELM_FILE_PATH}")/schema.json"
curl -fsSL "${HELM_RELEASE_SCHEMA_URL}" | jq --arg SCHEMA_URL "${SCHEMA_URL}" '.properties.spec.properties.values."$ref" = $SCHEMA_URL' > "${SCHEMA_PATH}"

# Patch the helm release to use the schema
PATCHED_FILE_CONTENTS="$(yq '. head_comment="yaml-language-server: $schema=./schema.json"' "${HELM_FILE_PATH}")"
# This is needed until https://github.com/mikefarah/yq/issues/2186 is fixed
cat << EOF > "${HELM_FILE_PATH}"
---
${PATCHED_FILE_CONTENTS}
EOF
