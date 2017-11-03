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

# Note - deliberately no 'set -e' in this file - if a test fails to run
# then we want to continue to try and run the rest of the tests

set -x

CURRENTDIR=$(dirname "$(readlink -f "$0")")
source "${CURRENTDIR}/../metrics/lib/common.bash"

REPORT_CMDS=("checkmetrics" "emailreport")

KSM_ENABLE_FILE="/sys/kernel/mm/ksm/run"
GITHUB_URL="https://github.com"
RESULTS_BACKUP_PATH="/var/local/localCI/backup"
RESULTS_DIR="${CURRENTDIR}/../metrics/results"

echo "In run_metrics_ci.sh - flags are [$-]"

# Set up the initial state
onetime_init

# Verify/install report tools. These tools will
# parse/send the results from metrics scripts execution.
for cmd in "${REPORT_CMDS[@]}"; do
	if ! command -v "$cmd" > /dev/null 2>&1; then
		pushd "$CURRENTDIR/../cmd/$cmd"
		make
		sudo make install
		popd
	fi
done

function timestamp_ns() {
	local t
	local s
	local n
	local ns

	t="$(date +%-s:%-N)"
	s=$(echo $t | awk -F ':' '{print $1}')
	n=$(echo $t | awk -F ':' '{print $2}')
	ns=$(( (s * 1000000000) + n ))

	echo $ns
}

# If we have influx avail, then we are running under Jenkins with the
# github PR plugin - post the PR details into the database as an annotation
# tag
if [[ $INFLUXDB_URL ]]; then
	timestamp=$(timestamp_ns)
	post_string="PR,repo=${ghprbGhRepository},PRId=${ghprbPullId} commit=\"${ghprbActualCommit}\" ${timestamp}"
	echo "Posting to $INFLUXDB_URL : ${post_string}"
	curl -i -XPOST $INFLUXDB_URL/write?db=$INFLUXDB_DB --data-binary "${post_string}"
fi

# Execute metrics scripts, save the results and report them
# by email.
pushd "$CURRENTDIR/../metrics"
	source "lib/common.bash"

	# If KSM is available on this platform, let's run the KSM tests first
	# and then turn it off for the rest of the tests, as KSM may introduce
	# some extra noise in the results by stealing CPU time for instance
	if [[ -f ${KSM_ENABLE_FILE} ]]; then
		# Ensure KSM is enabled
		sudo bash -c "echo 1 > ${KSM_ENABLE_FILE}"

		# Note - here we could set some default settings for KSM,
		# as on some distros KSM may either be set to rather passive
		# which affects the chosen 'settle time' of the tests

		# Run the memory footprint test. With default Ubuntu 16.04
		# settings, and 20 containers, it takes ~200s to 'settle' to
		# a steady memory footprint
		bash density/docker_memory_usage.sh 20 300

		# And now ensure KSM is turned off for the rest of the tests
		sudo bash -c "echo 0 > ${KSM_ENABLE_FILE}"
	fi

	# Run the time tests
	bash time/docker_workload_time.sh true busybox $RUNTIME 100

	# Run the memory footprint test
	# As we have no KSM here, we do not need a 'settle delay'
	bash density/docker_memory_usage.sh 20 1

	#
	# Run some network tests
	#

	# ops/second
	bash network/network-nginx-ab-benchmark.sh

	# ping latency
	bash network/network-latency.sh

	# Bandwidth and jitter
	bash network/network-metrics-iperf3.sh

	# UDP bandwidths and packet loss
	bash network/network-metrics-nuttcp.sh


	#
	# Run some IO tests
	#
	bash storage/fio_job.sh -b 16k -o randread -t "storage IO random read bs 16k"
	bash storage/fio_job.sh -b 16k -o randwrite -t "storage IO random write bs 16k"
	bash storage/fio_job.sh -b 16k -o read -t "storage IO linear read bs 16k"
	bash storage/fio_job.sh -b 16k -o write -t "storage IO linear write bs 16k"

	# Pull request URL
	PR_URL="$GITHUB_URL/$LOCALCI_REPO_SLUG/pull/$LOCALCI_PR_NUMBER"

	# Subject for emailreport tool about Pull Request
	SUBJECT="[${LOCALCI_REPO_SLUG}] metrics report (#${LOCALCI_PR_NUMBER})"

	# If we are running under LocalCI then do some housekeeping
	if [ ${LOCALCI} ]; then
		# Parse/Report results
		emailreport -c "Pull request: $PR_URL" -s "$SUBJECT"

		# Save the results directory in a backup path. The metrics tests will be
		# executed each new pull request or when a Pull Request has been modified,
		# then the results from the same Pull Request number will be identified
		# by epoch point time as name of the direcory.
		REPO="$(cut -d"/" -f2 <<<"$LOCALCI_REPO_SLUG")"
		PR_BK_RESULTS="$RESULTS_BACKUP_PATH/$REPO/$LOCALCI_PR_NUMBER"
		DEST="$PR_BK_RESULTS/$(date --iso-8601=seconds)"

		if [ ! -d "$PR_BK_RESULTS" ]; then
			mkdir -p "$PR_BK_RESULTS"
		fi

		mv "$RESULTS_DIR" "$DEST"
	fi

	# If we are running under Jenkins then do the Jenkins specific
	# tail end work
	if [ ${JENKINS_HOME} ]; then
		# Note the baseline toml file is tied to the machine name
		checkmetrics --basefile /etc/checkmetrics/checkmetrics-$(uname -n).toml --metricsdir ${RESULTS_DIR}
		# Check if we failed the test!
		cm_result=$?
		if [ ${cm_result} != 0 ]; then
			echo "checkmetrics FAILED (${cm_result})"
			exit ${cm_result}
		fi
	fi


popd

exit 0
