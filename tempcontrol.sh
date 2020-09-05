#!/bin/bash

# ----------------------------------------------------------------------------------
# This script controls the fans in a Dell R720xd based on CPU and ambient
# temperature readings from the server's iDRAC controller. Temperture is read using
# SNMPWALK. Optionally the temperature can be read using IPMITOOL but this is
# slower. Fan speed is set using IPMITOOL.
#
# The fan speed control utilizes a PID controller, but it only lowers the
# temperature if too high and does not try to increase it to meet the target.
#
# Requires:
# bc – sudo apt install bc
# snmpwalk - audo apt install snmp
# ipmitool – sudo apt install ipmitool
#
# Version 3 (Nov 28 2019)
# ----------------------------------------------------------------------------------


# IPMI SETTINGS:
IPMIHOST=192.168.0.39
IPMIUSER=your_username
IPMIPW=your_password

# SNMP settings
COMMUNITYNAME="your_community_name"

# TEMPERATURE
# If the CPU temperature goes above TARGETTEMP, use PID control to set fan speed.
TARGETTEMP=60

# PID (Proportional, Integral, Derivative). Adjust these 3 parameters to alter
# how the fan reacts to changes in temperature.
# Change in percent when an adjustment is made
Kp=1
# How much the change will be amplified based on the error
Ki=1
# The fan speed will be adjusted by this percent after a change in temp, multiplied bythe
# the error. The value will be zero if no change
Kd=1

# Fan speed in percent when the script is first started.
I_start=30

# Maximum fan speed in percent. Reduce I_max to a tolerable noise level, but don't
# go too low to prevent CPU throttling.
I_max=100

# Check status every pollinginterval seconds
pollinginterval=30

# Variable initialization
integral=$I_start
I_min=$I_start
LastError=0
derivative=0
LastFANSPEED=0

# Format data that is sent to journalctl log
dumpformat="PID=%3.0f (%3.0f/%3.0f/%3.0f) Der=%3.0f Int=%3.0f Err=%3.0f CPU=%2.0f Fan=%2.0f Lastspeed=%5.0f"

function PingHealthChecks () {
	curl -fsS --retry 3 https://hc-ping.com/your-special-id >/dev/null 2>&1
}

# Set the "idle speed" of the fans based on ambient temperature. If you don't want variable
# minimum fan speed, set I_min to a specific value in the variable initialization area and
# comment out this function in the main code.
function SetMinFanSpeed () {
	if [[ $AMBIENT -lt 23 ]]; then
	#set fan speed to 4000 / 15%
	  I_min=15
		else
		if [[ $AMBIENT -lt 24 ]]; then
		  #set fan speed to 4200 / 16%
			  I_min=16
			else
			if [[ $AMBIENT -lt 25 ]]; then
					  #set fan speed to 4560 / 18%
					  I_min=18
				else
				if [[ $AMBIENT -lt 26 ]]; then
						  #set fan speed to 4800 / 20%
						  I_min=20
						else
						if [[ $AMBIENT -lt 27 ]]; then
									  #set fan speed to 5500 / 25%
									  I_min=25
									  else I_min=30
						fi
				fi
			fi
		fi
	fi
	
	echo Setting MinFanSpeed to $I_min
}

# Write data to journalctl. 
function Write_Log() {
	printf "$dumpformat" $PID $P $I $D $LastError $integral $error $CPUTEMP $FANSPEED $FAN1 | systemd-cat -t TEMPCTRL
}

# Set fan speed 
function Write_Fan_Speed () {
	if [[ $FANSPEED -lt $I_min ]]; then
		FANSPEED=$I_min
	fi
	
	if [[ $FANSPEED -ne  $LastFANSPEED ]]; then
		ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW raw 0x30 0x30 0x01 0x00
		ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW raw 0x30 0x30 0x02 0xff $FANSPEED
		LastFANSPEED=$FANSPEED
		echo Set FANSPEED=$FANSPEED
	fi
}

# Set fan speed control to automatic. Currently not used in this script.
function Set_Fan_Auto () {
	ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW raw 0x30 0x30 0x01 0x01
	echo Fan control set to automatic
}

# Read server temperatures using IPMITOOL. Currently not used in this script.
function Get_Temperature_IPMI() {
	# This sends an IPMI command to get all the temperatures, and outputs it as two digits.
	ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW sdr type temperature > ipmitemp
	EXHAUST=$(cat ipmitemp |grep Exhaust |grep degrees |grep -Po '\d{2}' | tail -1)
	AMBIENT=$(cat ipmitemp |grep Inlet |grep degrees |grep -Po '\d{2}' | tail -1)
	CPU1=$(cat ipmitemp |grep 0Eh |grep degrees |grep -Po '\d{2}' | tail -1)
	CPU2=$(cat ipmitemp |grep 0Fh |grep degrees |grep -Po '\d{2}' | tail -1)
	FAN1=$(snmpwalk -c $COMMUNITYNAME -v 2c -Ovq $IPMIHOST 1.3.6.1.4.1.674.10892.5.4.700.12.1.6.1.1)
	
	echo Get IPMI Temp=$AMBIENT $EXHAUST $CPU1 $CPU2
	
	# Store the higher CPU temperature into variable called CPUTEMP
	if [[ $CPU1 -gt $CPU2 ]]; then
		CPUTEMP=$CPU1
		else
			CPUTEMP=$CPU2
	fi
}

# Read server temperatures using SNMPWALK. The OID will need to be customized for different server models,
# and possibly the math too.
function Get_Temperature_SNMP() {
	# OID for Dell R720xd
	AMBIENT=$(snmpwalk -c $COMMUNITYNAME -v 2c -Ovq $IPMIHOST 1.3.6.1.4.1.674.10892.5.4.700.20.1.6.1.1)
	EXHAUST=$(snmpwalk -c $COMMUNITYNAME -v 2c -Ovq $IPMIHOST 1.3.6.1.4.1.674.10892.5.4.700.20.1.6.1.2)
	CPU1=$(snmpwalk -c $COMMUNITYNAME -v 2c -Ovq $IPMIHOST 1.3.6.1.4.1.674.10892.5.4.700.20.1.6.1.3)
	CPU2=$(snmpwalk -c $COMMUNITYNAME -v 2c -Ovq $IPMIHOST 1.3.6.1.4.1.674.10892.5.4.700.20.1.6.1.4)
	FAN1=$(snmpwalk -c $COMMUNITYNAME -v 2c -Ovq $IPMIHOST 1.3.6.1.4.1.674.10892.5.4.700.12.1.6.1.1)

	AMBIENT=$(bc <<< "$AMBIENT*0.1")
	EXHAUST=$(bc <<< "$EXHAUST*0.1")
	CPU1=$(bc <<< "$CPU1*0.1")
	CPU2=$(bc <<< "$CPU2*0.1")
	echo Get SNMP Temp=$AMBIENT $EXHAUST $CPU1 $CPU2
	
	# Convert from floating point to integer. This truncates the decimal but
	# R720xd only returns integer results
	AMBIENT=${AMBIENT%.*}
	EXHAUST=${EXHAUST%.*}
	CPU1=${CPU1%.*}
	CPU2=${CPU2%.*}
	
	# Store the higher CPU temperature into variable called CPUTEMP
	if [[ $CPU1 -gt $CPU2 ]]; then
		CPUTEMP=$CPU1
		else
			CPUTEMP=$CPU2
	fi
}

function Update_PID() {
	error=$(bc <<< "-1*($TARGETTEMP-$CPUTEMP)")
	derivative=$(bc <<< "$error-(1*$LastError)")
	P=$(bc <<< "$Kp*$error")
	D=$(bc <<< "$Kd*$derivative")
	LastError=$error
	integral=$(bc <<< "$integral+$error")
	I=$(bc <<< "$Ki*$integral")
	
	if [[ $integral -gt $I_max ]]; then
		integral=$I_max
		elif [[ $integral -lt $I_min ]]; then
			integral=$I_min
	fi
	
	if [[ $error -lt 0 ]] || ([[ $error = 0 ]] && [[ $derivative = 0 ]]); then
		integral=$I_min
		echo Reset integral=$I_min
	fi
	
	PID=$(bc <<< "$P+$I+$D")
	echo PID=$PID P=$P I=$I D=$D Err=$error
}

# ---- MAIN MODULE ----

printf "Program Start. Target Temp=$TARGETTEMP. Min fan speed=$I_min\n" | systemd-cat -t TEMPCTRL

Get_Temperature_SNMP

while true; do

	# Use PID control when CPU temp goes above TARGETTEMP
	while [[ $CPUTEMP -gt $TARGETTEMP ]]; do

		Update_PID
		
		FANSPEED=$PID
		
		Write_Fan_Speed

		Write_Log

		echo Temperature greater than $TARGETTEMP. Setting fanspeed to $FANSPEED

		# healthchecks.io
		PingHealthChecks

		sleep $pollinginterval

		Get_Temperature_SNMP

	done

	# Change speed to I_min when CPU goes below target to minimize fan noise
	
	SetMinFanSpeed
	
	Update_PID
	
	FANSPEED=$I_min
	
	Write_Fan_Speed
	
	Write_Log

	# healthchecks.io
	PingHealthChecks
	
	sleep $pollinginterval

	Get_Temperature_SNMP

done

