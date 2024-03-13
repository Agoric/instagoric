# instagoric

## Local cluster

Optionally specify the Agoric SDK image tag.

1. kustomize edit set image agoric/agoric-sdk:dev

To deploy:

1. kubectl -n instagoric apply -k .

When finished:

1. kubectl delete namespace instagoric
