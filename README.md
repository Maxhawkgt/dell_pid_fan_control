# dell_r720xd_pid_fan_control

This repository has been recreated due to some errors on my part. I also took this opportunity to rename the old shell file from `tempcontrol3.sh` to `tempcontrol.sh` to keep the filename more generic and allow proper history.

## Change History
- **Nov 28 2019 (V3)**
  - Initial release
- **Sep 5 2020 (V5)**
  - Add functionality to increase minimum speed based on power consumption. This prevents the fan from cycling speeds during heavy loads
  - The power figures are based on the granularity of the power consumption jumps. On my server it changes in steps of 14ø

## Description
This script controls the fans in a Dell R720xd based on CPU and ambient temperature readings from the server's iDRAC controller. Temperture is read using `SNMPWALK`. Optionally the temperature can be read using `IPMITOOL` but I found this to slower than using SNMP. Fan speed is set using `IPMITOOL`.

This script is written in bash so it requires a program called `bc` (basic calculator) to do multiplication. You could port this to Python and you wouldn't need `bc`.

The OIDs used for SNMP are for a Dell R720xd. If you have a different server you will need to modify the `SNMPWALK` and `IPMITOOL` commands.

The fan speed control utilizes a PID controller, but it only lowers the temperature if too high and does not try to increase it to meet the target. Instead I have chosen to set low speed boundaries based on ambient temperature so that the CPU temperature can go way below the maximum temperature.

Kp, Ki, and Kd are gain parameters used to tune the behavior of the PID controller in response to temperature changes. You'll have to research these on your own to determine how to tune them. The descriptions in the comments of the script file were copied from another example and may not be correct.

## Required Tools
There are 3 tools you need to load into your machine:
1. BC - `sudo apt install bc`
2. SNMPWALK - `sudo apt install snmp`
3. IPMITOOL - `sudo apt install ipmitool`

There are echo commands that print debug commands to the screen when running this script from the command line.

## Run script as a service
I have this running in an Unbuntu 16.04 VM which uses systemd for services. Copy this file into */etc/systemd/system/tempcontrol.service* and set the path to your script:

```[Unit]
Description=Automatic fan control of R720xd
After=network.target

[Service]
Type=simple
ExecStart=/path-to-script/tempcontrol.sh &
ExecStopPost=/path-to-script/autofan.sh &
TimeoutSec=15
Restart=always

[Install]
WantedBy=multi-user.target
```

**To add and start the service:**

``sudo systemctl enable tempcontrol``

``sudo systemctl start tempcontrol``

**Set fan speed to automatic in event of failure**

I've not tested this, but `ExecStopPost` is supposed to execute when the service terminates improperly (not with SYSTEMCTL STOP) and `Restart=always` is supposed to restart the script in the event of a failure. 

The following is what I use to set fan speed control to automatic:

``ipmitool -I lanplus -H ipmi.ip.address -U username -P password raw 0x30 0x30 0x01 0x01``

## Logging

Each time the script polls the temperature and sets the fan speed, a line is written to journalctl with the heading TEMPCTRL. You can use the following command to view journalctl to see what tempcontrol3.sh is doing:

``journalctl -f -t TEMPCTRL``

Data being logged:

PID, P, I, D, Derivative, Integral, Error, MaxCPUtemp, Fan(%), prior fanspeed

## Monitoring

I use [healthchecks.io](http://healthchecks.io) to monitor if the script is running. The script calls a particular URL to tell healthchecks.io that it's still alive. If healthchecks.io doesn't get refreshed in a predetermined amount of time, a notification is sent.

Every once in a while healthchecks.io gets triggered and I can see in journalctl that a line or 2 (based on timestamp) are missing, but it always comes back. I've not been able to determine the root cause. It could have to do with other SNMP calls that are made by telegraf that does data collection for grafana.

