#!/bin/bash

#  Copyright (C) 2017 Intel Corporation
#
#  This program is free software; you can redistribute it and/or
#  modify it under the terms of the GNU General Public License
#  as published by the Free Software Foundation; either version 2
#  of the License, or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#

set -e

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/lib/network-common.bash"
source "${SCRIPT_PATH}/../lib/common.bash"

TEST_NAME="iperf3 udp scaling"

bandwidths=("10M" "20M" "40M" "80M" "100M" "400M" "800M" "1G" "2G" "4G" "8G" "10G")
packet_sizes=("22" "490" "1478")
ITERATIONS=5

cmds=("awk")

# Port number where the server will run
port="5201"
fwd_port="${port}:${port}"
# Image name
image="gabyct/network"
# Measurement time (seconds)
transmit_timeout=5
# Arguments to run the client/server
# "privileged" argument enables access to all devices on
# the host and it allows to avoid conflicts with AppArmor
# or SELinux configurations.
if [ "$RUNTIME" == "runc" ]; then
	extra_capability="--privileged"
fi

# Client/Server extra configuration
client_extra_args="$extra_capability --rm"
server_extra_args="$extra_capability"

# Iperf server configuration
# Set the TMPDIR to an existing tmpfs mount to avoid a 9p unlink error
# Note, this requires an upto date iperf3 >= v3.2 or thereabouts, which
# the gabyct/network image now has.
init_cmds="export TMPDIR=/dev/shm"
server_command="$init_cmds && iperf3 -s"

# Get the iperf3 server up and running
start_our_server() {
	server_address=$(start_server "$image" "$server_command" "$server_extra_args")

	# Verify server IP address
	if [ -z "$server_address" ];then
		clean_env
		die "server: ip address no found"
	fi

	sleep 3
}

# Run the iperf3 udp client with the parameters set in the global vars
client_udp_test() {

	local client_command="$init_cmds && iperf3 -c $server_address -u -l $packetsize -b $bandwidth"
	output=$(start_client "$image" "$client_command" "$client_extra_args")

	if [ -z "$output" ]; then
		die "no result output"
	fi

	# grab the receiver line - that is where we will see the errors
	result_line=$(echo "$output" | tail -3 | head -1)

	local transfer=$(awk '{print $5}' <<< $result_line)
	local transfer_units=$(awk '{print $6}' <<< $result_line)
	local bw=$(awk '{print $7}' <<< $result_line)
	local bw_units=$(awk '{print $8}' <<< $result_line)
	local lost=$(awk '{print $12}' <<< $result_line)
	# shell magic to strip the (%) off
	lost=${lost##*(}
	lost=${lost%\%)*}

	argstring="packetsize=$packetsize reqbandwidth=$bandwidth iteration=$iteration"
	argstring="$argstring transfer=$transfer transfer_units=$transfer_units"
	argstring="$argstring bandwidth=$bw bandwidth_units=$bw_units"
	save_results "${TEST_NAME}" "$argstring" "$lost" "%"
	# Note - this echo tacks on to the end of the main loop echo
	echo " : ${lost} %"
}

main()
{
	init_env
	check_cmds "${cmds[@]}"
	check_images "$image"

	start_our_server
	for packetsize in "${packet_sizes[@]}"; do
		for bandwidth in "${bandwidths[@]}"; do
			for iteration in $(seq 1 $ITERATIONS); do
				echo -n "test pktsz $packetsize bw $bandwidth iteration $iteration"
				client_udp_test
			done
		done
	done
}

main
