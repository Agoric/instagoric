#!/bin/bash

set -eux

CERTIFICATE_FILE=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
INTERVAL=$((60 * 60))
NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
OUTPUT_FILE="/tmp/$(date '+%s').json"
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

cleanup() {
    rm --force "$OUTPUT_FILE"
}

delete_pod() {
    local POD_NAME="$1"
    echo "Deleting pod $POD_NAME"

    curl "https://kubernetes.default.svc/api/v1/namespaces/$NAMESPACE/pods/$POD_NAME" \
     --cacert "$CERTIFICATE_FILE" \
     --header "Authorization: Bearer $TOKEN" \
     --header "Content-Type: application/json" \
     --request DELETE 2>/dev/null
}

delete_pods() {
    for pod_name in "${LINKED_PODNAMES[@]}"; do
        delete_pod "$pod_name"
        sleep "$INTERVAL"
    done
    delete_pod "$CURRENT_PODNAME"
}

extract_pod_names() {
    CURRENT_PODNAME=$(
        jq '.items[] | select(.metadata.ownerReferences[].kind == "StatefulSet") | select(.metadata.ownerReferences[].name == $EXCLUDE_POD) | .metadata.name' \
        --arg EXCLUDE_POD "$ROLE" --raw-output < "$OUTPUT_FILE"
    )

    # shellcheck disable=SC2207
    LINKED_PODNAMES=($(
        jq '.items[] | select(.metadata.ownerReferences[].kind == "StatefulSet") | select(.metadata.ownerReferences[].name != $EXCLUDE_POD) | .metadata.name' \
        --arg EXCLUDE_POD "$ROLE" --raw-output < "$OUTPUT_FILE"
    ))
}

get_all_pods_data() {
    curl "https://kubernetes.default.svc/api/v1/namespaces/$NAMESPACE/pods" \
     --cacert "$CERTIFICATE_FILE" \
     --header "Authorization: Bearer $TOKEN" \
     --header "Content-Type: application/json" \
     --output "$OUTPUT_FILE" \
     --request GET 2>/dev/null
}

get_all_pods_data
extract_pod_names
delete_pods
cleanup
