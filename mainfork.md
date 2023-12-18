# Introduction

Mainfork is a modified snapshot of the mainnet state, designed for creating a mainnet fork for testing purposes. 
As of December 2023, Mainfork instances are operational on two clusters: Ollinet and Xnet.

## Key Differences Between Mainfork and Mainnet Genesis

Mainfork genesis is derived from the mainnet export with specific alterations in `genesis.json`:

### Validators
- **Key Replacement:** Two mainnet validators' keys are replaced with new keys under our control.
- **Whale Delegator:** A new `whale` delegator is introduced, possessing a vast token amount. This delegator allocates substantial tokens to our two validators, making them the most powerful in the network.
- **Validator Names:** Names remain unchanged for easy identification.

### Voting Period
- The voting period has been shortened to 60 seconds.

### Tally Parameters
- Voting threshold and quorum are set to 0.000000000000000001, enabling any account with a single token to pass a proposal.

### Chain ID
- The chain ID is updated to `agoric-mainfork-1`.

## Mainfork Clusters

### Accessing the Clusters

1. **Login to a Cluster:**
   ```bash
   gcloud container clusters get-credentials [cluster-name] --region us-central1 --project simulationlab

Replace [cluster-name] with ollinet or xnet as needed.

2. List Pods:

```
kubectl get pods -n instagoric
```

Look for fork1-0 and fork2-0 pods running Mainfork instances.


3. Accessing Forks:

```
kubectl -n instagoric exec -it --tty fork1-0 -- /bin/bash
```

Replace [pod-name] with fork1-0 or fork2-0 as needed.

4. Check Validator Node Status:

```
agd status | jq .
```

In above command's output you can see that the current node is a validator node and got a massive voting power.


### API Endpoints

Ollinet: https://ollinet.agoric.net/
Xnet: https://xnet.agoric.net/

### Submitting a Proposal

1. Create an Account:
Before you can submit a proposal, you need to create an account and fund it with some tokens. You can create an account by running the following command:

```
agd keys add <account-name> --keyring-backend=test
```

2. Fund Wallet:

To fund with tokens, you can use the faucet at https://ollinet.faucet.agoric.net or https://xnet.faucet.agoric.net depending on your cluster.

3. Submit and Vote on Proposals:

Utilize regular agd commands. The low voting threshold allows passing proposals with minimal tokens.

After getting BLDs from above faucets, you can submit a proposal and vote with regular agd commands. Voting threshold is very small, so you can pass a proposal with a single token.

### Accessing superpowers

For developers, direct interaction with the whale account is typically unnecessary. However, if needed:


1. Start a shell into ollinet
```
kubectl -n instagoric exec -it --tty fork1-0 -- /bin/bash
```

2. List the keys

```
agd keys list --keyring-backend=test --home=/state/agoric-mainfork-1
```

3. Run a `agd` command as whale account

```
agd tx gov submit-proposal param-change <proposal-file> --from whale --chain-id agoric-mainfork-1 --home=/state/agoric-mainfork-1 -y -b block --keyring-backend=test
```

# Installation
To install mainfork instances a cluster, follow these steps:

1. Login to ollinet
`gcloud container clusters get-credentials [cluster-name] --region us-central1 --project simulationlab`

2. Install mainfork
`./init.sh [cluster-name]`


Replace  [cluster-name] with ollinet or xnet.

The last command will only update any config change in the mainfork and restart the pods, but the state from previous run will still be there. To start with a fresh state, you can run the following command before `./init.sh` command. 

*Warning:* This will delete all the data from the mainfork. So, only run this command if you want to start with a fresh state.

```
kubectl delete ns instagoric
```

# How is mainfork snapshot created?
There are multiple steps involved for creating a mainfork.
Here are those steps:

1. Create a new mainnet follower using state-sync.
2. Export the state of the follower.
3. Tinker the genesis.json in this exported state to add two powerfull validators.
4. Import the tinkered state into a new mainnet cluster with two validators.
5. Create a cosmos snapshot of this new mainnet cluster.

The code for creating mainfork snapshot is hosted at https://github.com/agoric-labs/cosmos-genesis-tinkerer

