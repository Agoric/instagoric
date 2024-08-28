#!/bin/bash

# Check if the required input is provided
if [ -z "$1" ]; then
  echo "Error: Missing input argument."
  echo "Usage: ./auto-approve.sh <ag_binary>"
  exit 1
fi

# Time interval between polls (in seconds)
POLL_INTERVAL=10
FROM_ACCOUNT=self
AG_BINARY="$1"

while true; do
    # Query for proposals with status "PROPOSAL_STATUS_VOTING_PERIOD"
    PROPOSALS=$($AG_BINARY query gov proposals --status VotingPeriod --chain-id=$CHAIN_ID --home=$AGORIC_HOME --output json 2> /dev/null)

    # Extract proposal IDs
    PROPOSAL_IDS=$(echo $PROPOSALS | jq -r '.proposals[].id')

    echo $PROPOSAL_IDS

    if [ -n "$PROPOSAL_IDS" ]; then
        for PROPOSAL_ID in $PROPOSAL_IDS; do
            echo "Voting YES on proposal ID: $PROPOSAL_ID"

            # Vote YES on the proposal
            $AG_BINARY tx gov vote $PROPOSAL_ID yes \
                --from=$FROM_ACCOUNT --chain-id=$CHAIN_ID --keyring-backend=test --home=$AGORIC_HOME --yes > /dev/null 2>&1

            echo "Voted YES on proposal ID: $PROPOSAL_ID"
        done
    else
        echo "No new proposals to vote on."
    fi

    # Wait for the next poll
    sleep $POLL_INTERVAL
done
