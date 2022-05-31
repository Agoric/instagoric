#! /bin/bash
v=validator-primary-0

from=${from-self}
keyopts=" --keyring-backend=test"

case $1 in
repl)
  kubectl exec ag-solo-manual-0 -- cat /state/agoric.repl
  exit $?
  ;;
console)
  shift
  grep '"type":"console"' ${1+"$@"} | \
    jq -rc '[(.time | todate), .source, (.args | join(" "))] | join(": ")'
  exit $?
  ;;
esac

if [ -z "$chainid" ]; then
  echo 1>&2 "Usage: chainid=agoricstage-27 $0 [--all] arguments"
  exit 1
fi

case $1 in
logs)
  shift
  cmd="cat"
  while [ $# -gt 0 ]; do
    case $1 in
    -f | --follow) cmd="tail -f" ;;
    -r | --reverse) cmd="tac" ;;
    *)
      if [ -z "$target" ]; then
        target=$1
      else
        echo 1>&2 "Usage: $0 logs [--follow] [--reverse] [target]"
        exit 1
      fi
      ;;
    esac
    shift
  done
  target=${target-validator-primary-0}
  kubectl exec "$target" -- bash -c "$cmd \$(ls /state/slogfile_*.json | tail -1)"
  ;;
esac


if [[ "$1" == "--all" ]]; then
  shift
  targets=
  for label in validator validator-primary; do
    targets="$targets $(kubectl -n instagoric get -l app=$label pods -o jsonpath='{.items[*].metadata.name}')"
  done
else
  targets="validator-primary-0"
fi

case $1 in
  keys)
    shift
    opts="keys $opts$keyopts"
    ;;
  tx)
    shift
    opts="tx $opts$keyopts --from=$from --chain-id=$chainid \
    --gas=auto --gas-adjustment=1.2 -b block --yes=true"
    ;;
esac

for v in $targets; do
  kubectl -n instagoric exec "$v" -- agd --home=/state/$chainid $opts ${1+"$@"}
done
