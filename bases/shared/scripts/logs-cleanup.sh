#! /bin/bash

ACCESS_TOKEN=""
BUCKET_NAME="agoric-chain-logs"
CURRENT_DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
EXCLUDED_FILES=("$@")
HEADER='{"alg":"RS256","typ":"JWT"}'
SCOPES="https://www.googleapis.com/auth/devstorage.read_write"
SERVICE_ACCOUNT_JSON="/config/secrets/logs-backup.json"
STATE_DIRECTORY_PATH="/state"
TOKEN_URI="https://oauth2.googleapis.com/token"
UPLOAD_TYPE="media"
UPLOAD_URL="https://storage.googleapis.com/upload/storage/v1/b"

base64url_encode() {
    openssl base64 -e -A |
        tr '+/' '-_' |
        tr --delete '='
}

ensure_can_generate_auth_token() {
    if ! test -f "$SERVICE_ACCOUNT_JSON"; then
        exit 0
    fi
}

generate_access_token() {
    CLIENT_EMAIL=$(
        jq '.client_email' \
            --raw-output <$SERVICE_ACCOUNT_JSON
    )
    EXPIRATION=$(("$BOOT_TIME" + 3600))
    HEADER_BASE64=$(echo -n "$HEADER" | base64url_encode)
    ISSUED_AT="$BOOT_TIME"
    PRIVATE_KEY=$(
        jq '.private_key' \
            --raw-output <$SERVICE_ACCOUNT_JSON |
            sed 's/\\n/\n/g'
    )

    PAYLOAD="{ \"aud\": \"$TOKEN_URI\", \"exp\": $EXPIRATION, \"iat\": $ISSUED_AT, \"iss\": \"$CLIENT_EMAIL\", \"scope\": \"$SCOPES\" }"

    PAYLOAD_BASE64=$(echo -n "$PAYLOAD" | base64url_encode)

    SIGNATURE=$(
        echo -n "${HEADER_BASE64}.${PAYLOAD_BASE64}" |
            openssl dgst -sha256 -sign <(echo -n "$PRIVATE_KEY") |
            base64url_encode
    )

    ACCESS_TOKEN="$(
        curl $TOKEN_URI \
            --data "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=$HEADER_BASE64.$PAYLOAD_BASE64.$SIGNATURE" \
            --header "Content-Type: application/x-www-form-urlencoded" --silent --request POST |
            jq --raw-output '.access_token'
    )"

}

main() {
    # shellcheck disable=SC2207,SC2010
    FILES=($(
        ls "$STATE_DIRECTORY_PATH" |
            grep --extended-regexp '^[[:alnum:]]+(_[[:alnum:]]+)*_[[:digit:]]+\.(log|json)+$'
    ))

    for file in "${FILES[@]}"; do
        file_path="$STATE_DIRECTORY_PATH/$file"
        if ! should_exclude_file "$file_path" "${EXCLUDED_FILES[@]}"; then
            upload_and_remove_file "$file" &
        fi
    done
}

should_exclude_file() {
    local file_to_check="$1"
    shift

    local excluded_file
    for excluded_file in "$@"; do
        [[ "$excluded_file" == "$file_to_check" ]] && return 0
    done

    return 1
}

upload_and_remove_file() {
    local file_name="$1"

    FILE_PATH="$STATE_DIRECTORY_PATH/$file_name"
    OBJECT_NAME="$CLUSTER_NAME/$NAMESPACE/$PODNAME/$CHAIN_ID/$file_name"

    FILE_SIZE=$(du --human-readable "$FILE_PATH" | cut --fields 1)

    echo "Uploading file '$OBJECT_NAME' of size $FILE_SIZE"
    HTTP_CODE=$(
        curl "$UPLOAD_URL/$BUCKET_NAME/o?name=$OBJECT_NAME&uploadType=$UPLOAD_TYPE" \
            --header "Authorization: Bearer $ACCESS_TOKEN" --output "/dev/null" \
            --request "POST" --silent \
            --upload-file "$FILE_PATH" --write-out "%{http_code}"
    )

    # shellcheck disable=SC2181
    if (($?)) || [ ! "$HTTP_CODE" -eq 200 ]; then
        echo "Failed to upload file '$FILE_PATH'"
    else
        echo "Deleting file '$FILE_PATH'"
        rm --force "$FILE_PATH"
    fi
}

# shellcheck source=./source.sh
source "$CURRENT_DIRECTORY_PATH/source.sh"

ensure_can_generate_auth_token
generate_access_token
main
