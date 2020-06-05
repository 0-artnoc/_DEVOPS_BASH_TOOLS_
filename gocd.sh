#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2020-03-27 19:16:35 +0000 (Fri, 27 Mar 2020)
#
#  https://github.com/harisekhon/bash-tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

# Start a quick local Concourse CI

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(dirname "$0")"

# shellcheck disable=SC1090
. "$srcdir/lib/utils.sh"

NUM_AGENTS=1

server="http://${GOCD_HOST:-localhost}:${GOCD_PORT:-8153}"
url="$server/go/pipelines#!/"
api="$server/go/api"

config="$srcdir/setup/gocd-docker-compose.yml"

if [ -f setup/gocd_config_repo.json ]; then
    repo_config=setup/gocd_config_repo.json
else
    repo_config="$srcdir/setup/gocd_config_repo.json"
fi

if ! type docker-compose &>/dev/null; then
    "$srcdir/install_docker_compose.sh"
fi

action="${1:-up}"
shift || :

#git_repo="$(git remote -v | grep github.com | sed 's/.*github.com/https:\/\/github.com/; s/ .*//')"
#repo="${git_repo##*/}"

opts=""
if [ "$action" = up ]; then
    opts="-d"
fi

# load .gocd.yaml from this github location
# doesn't work - see https://github.com/gocd/gocd/issues/7930
# also, caused gocd-server to be recreated from different repos due to this differing environment variable each time
# which is not ideal as we want to boot GoCD from any repo and then incrementally add any builds from other repos, or load all via:
#
# git_foreach_repo.sh gocd.sh
#
#if [ -n "$git_repo" ]; then
#    export CONFIG_GIT_REPO="$git_repo"
#fi

echo "Booting GoCD:"
docker-compose -f "$config" "$action" $opts "$@"
echo
if [ "$action" = down ]; then
    exit 0
fi

when_url_content "$url" '(?i:gocd)'
echo

while curl -sS "$server" | grep -q 'GoCD server is starting'; do
    tstamp 'waiting for server to finish starting up and remove message "GoCD server is starting"'
    sleep 3
done
echo

echo "(re)creating config repo:"
echo

config_repo="$(jq -r '.id' "$repo_config")"

echo "deleting config repo if already existing:"
curl "$api/admin/config_repos/$config_repo" \
     -H 'Accept:application/vnd.go.cd.v3+json' \
     -H 'Content-Type:application/json' \
     -X DELETE -sS || :
echo
echo

echo "creating config repo:"
curl "$api/admin/config_repos" \
     -H 'Accept:application/vnd.go.cd.v3+json' \
     -H 'Content-Type:application/json' \
     -X POST \
     -d @"$repo_config" -sS
echo
echo

# needs this header, otherwise gets 404
get_agents(){
    curl -sS "$api/agents" -H 'Accept: application/vnd.go.cd.v6+json'
}

echo "Waiting for agent(s) to register:"
while true; do
    #if get_agents | grep -q hostname; then
    if [ "$(get_agents | jq '._embedded.agents | length')" -ge $NUM_AGENTS ]; then
        echo
        break
    fi
    echo -n '.'
    sleep 1
done

echo "Enabling agent(s):"
echo
get_agents |
jq -r '._embedded.agents[] | [.hostname, .uuid] | @tsv' |
while read -r hostname uuid; do
    echo "enabling agent: $hostname"
    curl "$api/agents/$uuid" \
    -H 'Accept: application/vnd.go.cd.v6+json' \
    -H 'Content-Type: application/json' \
    -X PATCH \
    -d '{ "agent_config_state": "Enabled" }' -sS || :  # don't stop, try enabling all agents
    echo
done

echo
echo "GoCD URL:  $url"
echo
if is_mac; then
    open "$url"
fi
