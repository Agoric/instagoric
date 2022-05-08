#!/bin/bash

# shellcheck disable=SC2206
apis=( $API_URLS )
# shellcheck disable=SC2206
statuses=( $STATUS_URLS )
delay=${DELAY:-20}
if [[ "${#apis[@]}" != "${#statuses[@]}" ]]; then
    echo "mismatch between num of elements in API_URLS and STATUS_URLS"
    exit 1
fi
echo "Loaded ${#apis[@]} urls"
re='^[0-9]+$'

# shellcheck disable=SC2064
trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

for ((num=0;num<${#apis[@]};num++)); do
    (
        api=${apis[num]}
        status=${statuses[num]}
        confighash=$(echo "${status}" | shasum | awk '{print $1}')
        while :
        do
            if json=$(curl -m 15 -sS "${api}/status"); then
                if [[ "$(echo "$json" | jq -r .jsonrpc)" == "2.0" ]]; then 
                    if curheight=$(echo "$json" | jq -r .result.sync_info.latest_block_height); then
                        if chainid=$(echo "$json" | jq -r .result.node_info.network); then
                            if [[ $curheight =~ $re ]] ; then
                                echo -n "$chainid: $curheight "
                                safechain=$(echo "$chainid" | shasum | awk '{print $1}')
                                filename="/tmp/lastheight_${confighash}_${safechain}"
                                if [[ ! -f $filename ]]; then
                                    echo "$curheight" > "$filename"
                                    echo "first observation of ${api}"
                                else
                                    lastheight=$(cat "$filename")
                                    if (( curheight > lastheight )); then
                                        echo "$curheight" > "$filename"
                                        echo "new height"
                                        curl -m 15 -sS "${status}" 
                                    else
                                        echo "height did not change"
                                    fi
                                fi
                            fi
                        fi
                    fi
                fi
            fi
            sleep "$delay"
        done
    ) &
done
wait
