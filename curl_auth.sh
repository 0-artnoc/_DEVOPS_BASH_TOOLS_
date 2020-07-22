#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2019-01-02 21:08:12 +0000 (Wed, 02 Jan 2019)
#
#  https://github.com/harisekhon/bash-tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# used by utils.sh usage()
# shellcheck disable=SC2034
usage_description="Runs curl with either Kerberos SpNego (if \$KRB5 is set) or
a ram file descriptor using \$PASSWORD to avoid credentials being exposed via process list or command line logging

Requires prefixing url with http:// or https:// to work on older versions of curl in order to parse hostname
for constructing the authentication string to be specific to the host as using netrc default login doesn't always work
"


# shellcheck source=lib/utils.sh
. "$srcdir/lib/utils.sh"

# used by utils.sh usage()
# shellcheck disable=SC2034
usage_args="[<curl_options>] <url>"

if [ $# -lt 1 ]; then
    # shellcheck disable=SC2119
    usage
fi

for x in "$@"; do
    # shellcheck disable=SC2119
    case "$x" in
        -h|--help) usage
        ;;
    esac
done

check_bin curl

USERNAME="${USERNAME:-$USER}"

# Only do password mechanism and netrc_contents workaround if not using Kerberos
if [ -z "${KRB5:-${KERBEROS:-}}" ]; then
    if [ -z "${PASSWORD:-}" ]; then
        pass
    fi

# ==============================================
# option 1

# works on Mac but not on Linux, so going back to parsing the hostname and dynamic loading
# curl 7.64.1 (x86_64-apple-darwin19.0) libcurl/7.64.1 (SecureTransport) LibreSSL/2.8.3 zlib/1.2.11 nghttp2/1.39.2
# curl 7.35.0 (x86_64-pc-linux-gnu) libcurl/7.35.0 OpenSSL/1.0.1f zlib/1.2.8 libidn/1.28 librtmp/2.3
if is_curl_min_version 7.64; then
    netrc_contents="default login $USERNAME password $PASSWORD"
fi

# ==============================================
# option 2
#
#hosts="$(awk '{print $1}' < ~/.ssh/known_hosts 2>/dev/null | sed 's/,.*//' | sort -u)"

# use built-in echo if availble, cat is slow with ~1000 .ssh/known_hosts
#if help echo &>/dev/null; then
#    netrc_contents="$(for host in $hosts; do echo "machine $host login $USERNAME password $PASSWORD"; done)"
#else
#    # slow fallback with lots of forks
#    netrc_contents="$(for host in $hosts; do cat <<< "machine $host login $USERNAME password $PASSWORD"; done)"
#fi

# ==============================================
# option 3

# Instead of generating this for all known hosts above just do it for the host extracted from the args url now

if [ -z "${netrc_contents:-}" ]; then
    if ! [[ "$*" =~ :// ]]; then
        usage "http(s):// not specified in URL"
    fi

    host="$(grep -om 1 '://[^:\/[:space:]]\+' <<< "$*" | sed 's,://,,')"

    netrc_contents="machine $host login $USERNAME password $PASSWORD"
fi

# ==============================================

fi

if [ -n "${KRB5:-${KERBEROS:-}}" ]; then
    command curl -u : --negotiate "$@"
else
    command curl --netrc-file <(cat <<< "$netrc_contents") "$@"
fi
