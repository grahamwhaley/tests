#!/bin/bash

#set -x

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../lib/common.bash"

# the system 'free available' level where we stop running the tests, as otherwise
#  the system can crawl to a halt, and/or start refusing to launch new VMs anyway
# We choose 2G, as that is one of the default VM sizes for CC
MEM_CUTOFF=(2*1024*1024*1024)

# Set FORCE_KSM to have KSM enabled, configured to be aggressive, and triggered
# after each container launch
# This will get optimal memory page sharing, at the cost of CPU time
FORCE_KSM=1

KSM_BASE_DIR=/sys/kernel/mm/ksm
KSM_ENABLE_FILE=${KSM_BASE_DIR}/run
KSM_PAGES_FILE=${KSM_BASE_DIR}/pages_to_scan
KSM_PAGES_TO_SCAN=100000
KSM_SLEEP_FILE=${KSM_BASE_DIR}/sleep_millisecs
KSM_PAGE_SCAN_TIME_MS=1

#PAYLOADS=(busybox alpine nginx mysql elasticsearch)
#PAYLOAD_SLEEPS=(0 0 5 15 15)
#PAYLOAD_MEMORY=(64M 64M 2048M 512M 8192M)
#PAYLOAD_ARGS=("tail -f /dev/null" "tail -f /dev/null" "" "" "")
#EXTRA_ARGS=("" "" "" "-e MYSQL_ALLOW_EMPTY_PASSWORD=1" "")

PAYLOADS=(elasticsearch)
PAYLOAD_SLEEPS=(15)
PAYLOAD_MEMORY=(8192M)
PAYLOAD_ARGS=("")
EXTRA_ARGS=("--cpus 1")

#PAYLOADS=(mysql)
#PAYLOAD_SLEEPS=(15)
#PAYLOAD_MEMORY=(512M)
#PAYLOAD_ARGS=("")
#EXTRA_ARGS=("--cpus 1 -e MYSQL_ALLOW_EMPTY_PASSWORD=1")

#PAYLOADS=(busybox)
#PAYLOAD_SLEEPS=(1)
#PAYLOAD_MEMORY=(64M)
#PAYLOAD_ARGS=("tail -f /dev/null")
#EXTRA_ARGS=("--cpus 1")

# Which runtime do we fall to by default
# We could just go with whatever the 'docker default' is, but better we
# actually know, and then we can record that in the results
#DEFAULT_RUNTIME="cc-runtime"
DEFAULT_RUNTIME="runc"

DEFAULT_MAX_CONTAINERS=100

REQUIRED_COMMANDS="docker"

# Sometimes we want to take a nap between launches to allow things to
# settle - such as containers starting up, or KSM settling down
LAUNCH_NAP=0

function die() {
	# right now we will fail many tests (like is qemu running) if we are not
	# using a Clear Container runtime - as an interim bodge, don't quit in that
	# case, just spew the warnings.
	if [[ $DEFAULT_RUNTIME != "runc" ]]; then
		exit -1
	fi
}

function check_all_running() {
	how_many=$1
	echo Checking ${how_many} containers are running

	# check what docker thinks
	how_many_running=$(count_containers)

	if (( ${how_many_running} != ${how_many} )); then
		echo "Wrong number of containers running (${how_many_running} != ${how_many} - stopping"
		# We hard exit here - no matter what runtime we should have the right number
		# of containers running
		exit -1
	fi

	# check we have the right number of proxy's
	# we should have 1 proxy running, iff we have >= 1 container running
	how_many_proxys=$(ps --no-header -C cc-proxy | wc -l)
	if (( ${how_many_running} >= 1 )); then
		if (( ${how_many_proxys} != 1 )); then
			# Need to check if the proxy is mean to quit if there are no containers running?
			# Until then make this a non fatal warning
			echo "Warning: Wrong number of proxys running (${how_many_running} containers, ${how_many_proxys} proxys)"
		fi
	else
		if (( ${how_many_proxys} != 0 )); then
			# Need to check if the proxy is mean to quit if there are no containers running?
			# Until then make this a non fatal warning
			echo "Warning: Wrong number of proxys running (${how_many_running} containers, ${how_many_proxys} proxys - stopping)"
		fi
	fi

	# check we have the right number of shims
	how_many_shims=$(ps --no-header -C cc-shim | wc -l)
	# two shim processes per container...
	if (( ${how_many_running}*2 != ${how_many_shims} )); then
		echo "Wrong number of shims running (${how_many_running}*2 != ${how_many_shims} - stopping)"
		die
	fi

	# check we have the right number of qemu's
	how_many_qemus=$(ps --no-header -C qemu-lite-system-x86_64 | wc -l)
	if (( ${how_many_running} != ${how_many_qemus} )); then
		echo "Wrong number of qemus running (${how_many_running} != ${how_many_qemus} - stopping)"
		die
	fi

	# check we have no runtimes running (they should be transient, we should not 'see them')
	how_many_runtimes=$(ps --no-header -C cc-runtime | wc -l)
	if (( ${how_many_runtimes} )); then
		echo "Wrong number of runtimes running (${how_many_runtimes} - stopping)"
		die
	fi
}

# somewhat harsh...
function kill_all_containers() {
	# two stage remove is 'safer' and nicer than a `rm -f`
	# also see: https://github.com/clearcontainers/tests/issues/492
	running=$(docker ps -q | wc -l)
	if ((${running})); then
		docker stop $(docker ps -qa)
	fi

	stopped=$(docker ps -qa | wc -l)
	if ((${stopped})); then
		docker rm $(docker ps -qa)
	fi
	#docker rm -f $(docker ps -qa)
}

# Turn on and configure KSM
function enable_ksm() {
	if [[ ! -f ${KSM_ENABLE_FILE} ]]; then
		echo "Warning: no KSM to enable"
		return
	fi

	echo "Enabling and configuring KSM"

	# Set the pages to scan as a silly large number
	sudo -E bash -c "echo ${KSM_PAGES_TO_SCAN} > ${KSM_PAGES_FILE}"

	# And scan a lot....
	sudo -E bash -c "echo ${KSM_PAGE_SCAN_TIME_MS} > ${KSM_SLEEP_FILE}"

	# And turn on KSM
	sudo -E bash -c "echo 1 > ${KSM_ENABLE_FILE}"

}

function disable_ksm() {
	if [[ ! -f ${KSM_ENABLE_FILE} ]]; then
		echo "Warning: no KSM to disable"
		return
	fi

	echo "Disabling KSM"
	# And turn off KSM
	sudo -E bash -c "echo 0 > ${KSM_ENABLE_FILE}"

}

# Kick KSM to run
# Note, it is not super clear from the docs or code that this does actually
# do an instant fire, even if KSM is already enabled - but, we have an aggresive
# timer period anyhow - let's try it
function tickle_ksm() {
	sudo -E bash -c "echo 1 > ${KSM_ENABLE_FILE}"
}

# Checks and setup.
function init() {

	kill_all_containers
	check_cmds $REQUIRED_COMMANDS

	echo "Pre-pulling images..."
	for image in ${PAYLOADS[@]}; do
		docker pull $image
	done

	how_many=0

	if [[ ${FORCE_KSM} ]]; then
		enable_ksm
	else
		disable_ksm
	fi
	
}

function get_system_avail() {
	echo $(free -b | head -2 | tail -1 | awk '{print $7}')
}

function count_containers() {
	docker ps -qa | wc -l
}

function go() {
	echo "Running..."

	how_many=0
	echo "number, available, time" > ${RESULTS_FILE}

	while true; do {
		check_all_running $how_many

		echo "Run $RUNTIME: -m $MEMORY $PAYLOAD: $COMMAND"
		how_long=$(/usr/bin/time -f "%e" docker run --runtime=${RUNTIME} -tid ${DOCKER_ARGS} -m ${MEMORY} ${PAYLOAD} ${COMMAND} 2>&1 1>/dev/null)

		# And fire KSM if needed before/whilst we nap
		if [[ ${FORCE_KSM} ]]; then
			tickle_ksm
		fi

		# Take the nap
		sleep $LAUNCH_NAP
		how_much=$(get_system_avail)

		((how_many++))

		echo "Container ${how_many} took ${how_long} and left ${how_much} free"

		how_many_running=$(count_containers)

		if (( ${how_many_running} != ${how_many} )); then
			echo "Wrong number of containers running (${how_many_running} != ${how_many} - stopping"
			return
		fi

		# number, mem, speed
		echo "$how_many, $how_much, $how_long" >> ${RESULTS_FILE}

		if (( ${how_many} > ${DEFAULT_MAX_CONTAINERS} )); then
			echo "And we have hit the max ${how_many} containers"
			return
		fi

		if (( ${how_much} < ${MEM_CUTOFF} )); then
			echo "And we are out of memory on container ${how_many} (${how_much} < ${MEM_CUTOFF})"
			return
		fi
	}
	done
}

function clean_up() {
	kill_all_containers
}

function run_packages() {
	package_n=0
	for package in ${PAYLOADS[@]}; do
		args=${PAYLOAD_ARGS[$package_n]}
		sleeps=${PAYLOAD_SLEEPS[$package_n]}
		memory=${PAYLOAD_MEMORY[$package_n]}
		dockerargs=${EXTRA_ARGS[$package_n]}

		echo "Run package $package, args ($args), sleep ($sleeps)"

		PAYLOAD=$package
		COMMAND=$args
		RESULTS_FILE="results-${RUNTIME}-${PAYLOAD}.csv"
		LAUNCH_NAP=$sleeps
		MEMORY=$memory
		DOCKER_ARGS=$dockerargs
		go
		clean_up

		((package_n++))
	done
}

RUNTIME=${DEFAULT_RUNTIME}
init
run_packages

