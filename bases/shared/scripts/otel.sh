#! /bin/bash

set -o nounset

ARCHITECTURE="$(dpkg --print-architecture)"
CONTAINER_ID=""
LOGS_FILE_PATH="$1"
OTEL_CONFIG="$HOME/instagoric-otel-config.yaml"
OTEL_RELEASE_SOURCE="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download"

# shellcheck source=./source.sh
source "$CURRENT_DIRECTORY_PATH/source.sh"

install_otel() {
    local zip_path="/tmp/otel.tgz"

    curl "$OTEL_RELEASE_SOURCE/v${OTEL_VERSION}/otelcol-contrib_${OTEL_VERSION}_linux_${ARCHITECTURE}.tar.gz" \
        --location --output "$zip_path"
    tar --directory "$HOME" --extract --file "$zip_path" --gzip

    rm --force "$zip_path"
}

main() {
    if test -z "$ENABLE_TELEMETRY"; then
        echo "skipping telemetry since ENABLE_TELEMETRY is not set"
        unset "OTEL_EXPORTER_OTLP_ENDPOINT"
        unset "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"
    elif test -f "$USE_OTEL_CONFIG"; then
        install_otel
        wait_for_container_id
        substitue_values_in_config
        start_server
    fi
}

start_server() {
    "$HOME/otelcol-contrib" --config "$OTEL_CONFIG" >>"$LOGS_FILE_PATH" 2>&1
}

substitue_values_in_config() {
    sed "$USE_OTEL_CONFIG" \
        --expression "s/@CHAIN_ID@/$CHAIN_ID/" \
        --expression "s/@CLUSTER_NAME@/$CLUSTER_NAME/" \
        --expression "s/@CONTAINER_ID@/$CONTAINER_ID/" \
        --expression "s/@NAMESPACE@/$NAMESPACE/" \
        --expression "s/@PODNAME@/$PODNAME/" \
        >"$OTEL_CONFIG"
}

wait_for_container_id() {
    while true; do
        CONTAINER_ID="$(
            curl "$API_ENDPOINT/api/v1/namespaces/$NAMESPACE/pods?labelSelector=statefulset.kubernetes.io/pod-name%3D$PODNAME" \
                --cacert "$CA_PATH" --header "Authorization: Bearer $(cat "$TOKEN_PATH")" --silent |
                jq --raw-output ".items[] | .status.containerStatuses[] | select(.name == '$CONTAINER_NAME') | .containerID" |
                sed --expression "s|containerd://||g"
        )"

        if test "$CONTAINER_ID" == "null"; then
            sleep 5
        else
            echo "Current Container ID: $CONTAINER_ID"
        fi
    done
}

main
