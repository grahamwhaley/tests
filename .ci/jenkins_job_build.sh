#!/bin/bash
#
# Copyright (c) 2017 Intel Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

# Need the repo to know which tests to run.
cc_repo=$1

tests_repo="github.com/clearcontainers/tests"

export GOPATH=${WORKSPACE}/go
mkdir -p ${GOPATH}

# Export all environment variables needed.
export GOROOT="/usr/local/go"
export PATH=${GOPATH}/bin:/usr/local/go/bin:/usr/sbin:${PATH}
export CI=true

# Download and build goveralls binary in case we need to submit the code
# coverage.
if [ ${COVERALLS_REPO_TOKEN} ]
then
	go get github.com/mattn/goveralls
fi

# Get the repository and move HEAD to the appropriate commit.
go get ${cc_repo} || true
pushd ${GOPATH}/src/${cc_repo}
if [ ${ghprbPullId} ] && [ ${ghprbTargetBranch} ]
then
	git fetch origin pull/${ghprbPullId}/head && git checkout FETCH_HEAD && git rebase origin/${ghprbTargetBranch}
else
	git fetch origin && git checkout origin/master
fi

# Setup and run the tests.
if [ "${cc_repo}" == "${tests_repo}" ]
then
        .ci/setup_tests.sh
fi

.ci/setup.sh

if [ -z "${METRICS_CI}" ]
then
	.ci/run.sh
else
	echo "Under METRICS_CI - skipping test run"
fi

# Publish the code coverage if needed.
if [ ${COVERALLS_REPO_TOKEN} ]
then
	sudo -E PATH=${PATH} bash -c "${GOPATH}/bin/goveralls -repotoken=${COVERALLS_REPO_TOKEN} -coverprofile=profile.cov"
fi

popd
