#!/bin/bash

#set -x

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../lib/common.bash"

# the system 'free available' level where we stop running the tests, as otherwise
#  the system can crawl to a halt, and/or start refusing to launch new VMs anyway
# We choose 2G, as that is one of the default VM sizes for CC
MEM_CUTOFF=(2*1024*1024*1024)

# The default container/workload we run for testing
# We generally choose busybox as it is 'small'
DEFAULT_PAYLOAD="busybox"

PAYLOADS=(busybox alpine nginx mysql elasticsearch)
PAYLOAD_SLEEPS=(0 0 5 15 15)
PAYLOAD_ARGS=("tail -f /dev/null" "tail -f /dev/null" "" "" "")
EXTRA_ARGS=("" "" "" "-e MYSQL_ALLOW_EMPTY_PASSWORD=1" "")

# The default command we run in the workload.
# Ideally something benign that does not consume memory or CPU
DEFAULT_COMMAND="tail -f /dev/null"

# Which runtime do we fall to by default
# We could just go with whatever the 'docker default' is, but better we
# actually know, and then we can record that in the results
#DEFAULT_RUNTIME="runc"
DEFAULT_RUNTIME="cor"

DEFAULT_MAX_CONTAINERS=10

REQUIRED_COMMANDS="docker"

# Sometimes we want to take a nap between launches to allow things to
# settle - such as containers starting up, or KSM settling down
LAUNCH_NAP=0


# somewhat harsh...
function kill_all_containers() {
	#docker stop $(docker ps -qa)
	#docker rm $(docker ps -qa)
	docker rm -f $(docker ps -qa)
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
	
}

function check_all_running() {
	echo Checking ${how_many} containers are running
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
		check_all_running

		echo "Run $RUNTIME: $PAYLOAD: $COMMAND"
		how_long=$(/usr/bin/time -f "%e" docker run --runtime=${RUNTIME} -tid ${DOCKER_ARGS} ${PAYLOAD} ${COMMAND} 2>&1 1>/dev/null)
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
		dockerargs=${EXTRA_ARGS[$package_n]}

		echo "Run package $package, args ($args), sleep ($sleeps)"

		PAYLOAD=$package
		COMMAND=$args
		RESULTS_FILE="results-${RUNTIME}-${PAYLOAD}.csv"
		LAUNCH_NAP=$sleeps
		DOCKER_ARGS=$dockerargs
		go
		clean_up

		((package_n++))
	done
}

RUNTIME=${DEFAULT_RUNTIME}
init
run_packages

