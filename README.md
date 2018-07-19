# nagios-plugin-check_tasmota

## check_tasmota

### EN

Nagios plugin to check Wifiplugs and attached sensors running Tasmota Firmware

With the values and the status, performance values will be provided too. 
Using these performance values, it is easy to provide long-term statistics.


### Usage

```
check_tasmota -u|--url <http://host:port> -a|--attributes <attributes> 
    [ -c|--critical <thresholds> ] [ -w|--warning <thresholds> ] 
    [ -P|--Password ] 
    [ -D|--SensorDevice ] 
    [ -S|--Sensor ] 
    [ -t|--timeout <timeout> ] 
    [ -h|--help ] 
```
	
### Example

```
./check_tasmota.pl --url http://192.168.178.10 -D Power --warning :0 --critical :1

./check_tasmota.pl --url http://192.168.178.10 -D ENERGY -S Power --warning :5 --critical :10 
```

Nagios Configuration can be found in folder EXAMPLE

### Release notes

#### 1.1

- Added Power (W) to ENERGY Sensor
