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

set -x

CURRENTDIR=$(dirname "$(readlink -f "$0")")
source "${CURRENTDIR}/../metrics/lib/common.bash"

REPORT_CMDS=("checkmetrics" "emailreport")

KSM_ROOT="/sys/kernel/mm/ksm"
KSM_ENABLE_FILE="${KSM_ROOT}/run"
KSM_PAGES_FILE="${KSM_ROOT}/pages_to_scan"
KSM_MILLI_FILE="${KSM_ROOT}/sleep_millisecs"
GITHUB_URL="https://github.com"
RESULTS_BACKUP_PATH="/var/local/localCI/backup"
RESULTS_DIR="results"

function ksm_footprint_test() {
	local pages_to_scan
	local sleep_milliseconds
	# Remember initial settings
	pages_to_scan=$(sudo cat ${KSM_PAGES_FILE})
	sleep_milliseconds=$(sudo cat ${KSM_MILLI_FILE})

	# Reconfigure to somewhat aggressive
	# We run 20 containers of maybe 2Mb, which is 500 pages each
	# That is 10,000 pages
	# And we'd like to scan them all in <10s
	# So, let's try 1000 pages/s - so 100 pages every 10ms might do it...
		# Scan every 10 milliseconds
	sudo bash -c "echo 10 > ${KSM_MILLI_FILE}"
		# And scan 100 pages
	sudo bash -c "echo 100 > ${KSM_PAGES_FILE}"

	# Ensure KSM is enabled
	sudo bash -c "echo 1 > ${KSM_ENABLE_FILE}"

	# Run the memory footprint test.
	# With the settings above, we should settle down KSM in <20s
	bash -$- density/docker_memory_usage.sh 20 20

	# And now ensure KSM is turned off for the rest of the tests
	sudo bash -c "echo 0 > ${KSM_ENABLE_FILE}"

	# And put back the defaults...
	sudo bash -c "echo ${sleep_milliseconds} > ${KSM_MILLI_FILE}"
	sudo bash -c "echo ${pages_to_scan} > ${KSM_PAGES_FILE}"
}

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

# Execute metrics scripts, save the results and report them
# by email.
pushd "$CURRENTDIR/../metrics"
	source "lib/common.bash"

	# If KSM is available on this platform, let's run the KSM tests first
	# and then turn it off for the rest of the tests, as KSM may introduce
	# some extra noise in the results by stealing CPU time for instance
	if [[ -f ${KSM_ENABLE_FILE} ]]; then
		ksm_footprint_test
	fi

	# Run the time tests
	bash -$- time/docker_workload_time.sh true busybox $RUNTIME 100

	# Run the memory footprint test
	# As we have no KSM here, we do not need a 'settle delay'
	bash -$- density/docker_memory_usage.sh 20 1

	#
	# Run some network tests
	#

	# ops/second
	bash -$- network/network-nginx-ab-benchmark.sh

	# ping latency
	bash -$- network/network-latency.sh

	# Bandwidth and jitter
	bash -$- network/network-metrics-iperf3.sh

	# UDP bandwidths and packet loss
	bash -$- network/network-metrics-nuttcp.sh


	#
	# Run some IO tests
	#
	bash -$- storage/fio_job.sh -b 16k -o randread -t "storage IO random read bs 16k"
	bash -$- storage/fio_job.sh -b 16k -o randwrite -t "storage IO random write bs 16k"
	bash -$- storage/fio_job.sh -b 16k -o read -t "storage IO linear read bs 16k"
	bash -$- storage/fio_job.sh -b 16k -o write -t "storage IO linear write bs 16k"

	# Pull request URL
	PR_URL="$GITHUB_URL/$LOCALCI_REPO_SLUG/pull/$LOCALCI_PR_NUMBER"

	# Subject for emailreport tool about Pull Request
	SUBJECT="[${LOCALCI_REPO_SLUG}] metrics report (#${LOCALCI_PR_NUMBER})"

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


popd

exit 0
