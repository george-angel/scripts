#!/bin/bash

set -euo pipefail

source "${GHA_SCRIPTS_DIR}/.github/workflows/common.sh"

prepare_git_repo

if ! check_remote_branch "docker-${VERSION_NEW}-${TARGET_BRANCH}"; then
    echo "remote branch already exists, nothing to do"
    exit 0
fi

pushd "${SDK_OUTER_OVERLAY}"

VERSION_OLD=$(sed -n "s/^DIST docker-\([0-9]*.[0-9]*.[0-9]*\).*/\1/p" app-containers/docker/Manifest | sort -ruV | head -n1)
if [[ "${VERSION_NEW}" = "${VERSION_OLD}" ]]; then
    echo "already the latest Docker, nothing to do"
    exit 0
fi

# we need to update not only the main ebuild file, but also its DOCKER_GITCOMMIT,
# which needs to point to COMMIT_HASH that matches with $VERSION_NEW from upstream docker-ce.
dockerEbuildOld=$(get_ebuild_filename app-containers/docker "${VERSION_OLD}")
dockerEbuildNew="app-containers/docker/docker-${VERSION_NEW}.ebuild"
git mv "${dockerEbuildOld}" "${dockerEbuildNew}"
sed -i "s/GIT_COMMIT=\(.*\)/GIT_COMMIT=${COMMIT_HASH_MOBY}/g" "${dockerEbuildNew}"
sed -i "s/v${VERSION_OLD}/v${VERSION_NEW}/g" "${dockerEbuildNew}"

cliEbuildOld=$(get_ebuild_filename app-containers/docker-cli "${VERSION_OLD}")
cliEbuildNew="app-containers/docker-cli/docker-cli-${VERSION_NEW}.ebuild"
git mv "${cliEbuildOld}" "${cliEbuildNew}"
sed -i "s/GIT_COMMIT=\(.*\)/GIT_COMMIT=${COMMIT_HASH_CLI}/g" "${cliEbuildNew}"
sed -i "s/v${VERSION_OLD}/v${VERSION_NEW}/g" "${cliEbuildNew}"

# update also docker versions used by the current runc ebuild file.
versionRunc=$(sed -n "s/^DIST runc-\([0-9]*.[0-9]*.*\)\.tar.*/\1/p" app-containers/runc/Manifest | sort -ruV | head -n1)
runcEbuildFile=$(get_ebuild_filename app-containers/runc "${versionRunc}")
sed -i "s/github.com\/docker\/docker-ce\/blob\/v${VERSION_OLD}/github.com\/docker\/docker-ce\/blob\/v${VERSION_NEW}/g" ${runcEbuildFile}

popd

# URL for Docker release notes has a specific format of
#   https://docs.docker.com/engine/release-notes/MAJOR.MINOR/#COMBINEDFULLVERSION
# To get the subfolder part MAJOR.MINOR, drop the patchlevel of the semver.
#   e.g. 20.10.23 -> 20.10
# To get the combined full version, drop all dots from the full version.
#   e.g. 20.10.23 -> 201023
# So the result becomes like:
#   https://docs.docker.com/engine/release-notes/20.10/#201023
URLSUBFOLDER=${VERSION_NEW%.*}
URLVERSION="${VERSION_NEW//./}"
URL="https://docs.docker.com/engine/release-notes/${URLSUBFOLDER}/#${URLVERSION}"

generate_update_changelog 'Docker' "${VERSION_NEW}" "${URL}" 'docker'

regenerate_manifest app-containers/docker-cli "${VERSION_NEW}"
commit_changes app-containers/docker "${VERSION_OLD}" "${VERSION_NEW}" \
               app-containers/docker-cli \
               app-containers/runc

cleanup_repo

echo "VERSION_OLD=${VERSION_OLD}" >>"${GITHUB_OUTPUT}"
echo 'UPDATE_NEEDED=1' >>"${GITHUB_OUTPUT}"
