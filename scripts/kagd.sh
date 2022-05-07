#! /bin/bash
v=validator-primary-0

from=${from-self}
keyopts=" --keyring-backend=test"

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
    -f | --follow) cmd="tail -f -n 100" ;;
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
  kubectl exec "$target" -- bash -c "$(cat <<EOF
$cmd \$(ls /state/slogfile_*.json | tail -1) | \
  grep '"type":"console"' | \
  jq -rc '[(.time | todate), .source, (.args | join(" "))] | join(": ")'
EOF
)"
  exit $?
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
    opts="$opts$keyopts"
    ;;
  tx)
    opts="$opts$keyopts --from=$from --chain-id=$chainid \
    --gas=auto --gas-adjustment=1.2 -b block --yes"
    ;;
esac

for v in $targets; do
  kubectl -n instagoric exec "$v" -- agd --home=/state/$chainid ${1+"$@"} $opts
done
