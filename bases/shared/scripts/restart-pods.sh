#! /bin/bash

set -o errexit -o nounset -o xtrace

CERTIFICATE_FILE="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
CURRENT_STATEFUL_SET="$ROLE"
INTERVAL="$((60 * 60))"
NAMESPACE="$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)"
TOKEN="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
OUTPUT_FILE="/tmp/$(date '+%s').json"
VOID="/dev/null"

clean_up() {
    rm --force "$OUTPUT_FILE"
}

get_all_stateful_sets() {
    curl "https://kubernetes.default.svc/apis/apps/v1/namespaces/$NAMESPACE/statefulsets" \
     --cacert "$CERTIFICATE_FILE" \
     --header "Accept: application/json" \
     --header "Authorization: Bearer $TOKEN" \
     --output "$OUTPUT_FILE" \
     --request "GET" 2> "$VOID"
}

main() {
    get_all_stateful_sets

    # shellcheck disable=SC2207
    OTHER_STATEFUL_SET=($(
        jq '.items[] | select(.metadata.name != $exclude_stateful_set) | .metadata.name' \
         --arg exclude_stateful_set "$CURRENT_STATEFUL_SET" --raw-output < "$OUTPUT_FILE"
    ))

    for stateful_set in "${OTHER_STATEFUL_SET[@]}"; do
        trigger_rollout_restart "$stateful_set"
        echo "Sleeping for $INTERVAL seconds..."
        sleep "$INTERVAL"
    done

    trigger_rollout_restart "$CURRENT_STATEFUL_SET"

    clean_up
    echo "Restart triggered for all stateful sets"
}

trigger_rollout_restart() {
    local PATCH_JSON
    local STATEFUL_SET_NAME="$1"
    local TIMESTAMP

    echo "Triggering background rollout restart for StatefulSet: $STATEFUL_SET_NAME"

    TIMESTAMP="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

    PATCH_JSON="{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"kubectl.kubernetes.io/restartedAt\":\"$TIMESTAMP\"}}}}}"

    curl "https://kubernetes.default.svc/apis/apps/v1/namespaces/$NAMESPACE/statefulsets/$STATEFUL_SET_NAME" \
     --cacert "$CERTIFICATE_FILE" \
     --header "Authorization: Bearer $TOKEN" \
     --header "Content-Type: application/strategic-merge-patch+json" \
     --data "$PATCH_JSON" \
     --request "PATCH" 2> "$VOID"
}

main
