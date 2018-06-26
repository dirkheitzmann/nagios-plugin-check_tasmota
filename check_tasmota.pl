#!/usr/bin/env perl

use warnings;
use strict;
use HTTP::Request::Common;
use LWP::UserAgent;
use JSON;
use Nagios::Plugin;
use Data::Dumper;
use Encode;
use HTTP::Cookies;
use Switch;

use constant { true => 1, false => 0 };


my $np = Nagios::Plugin->new(
    usage => "Usage: %s -u|--url <http://host:port> -a|--attributes <attributes> "
    . "[ -c|--critical <thresholds> ] [ -w|--warning <thresholds> ] "
    . "[ -P|--Password ] "
    . "[ -D|--SensorDevice ] " 
    . "[ -S|--Sensor ] " 
    . "[ -t|--timeout <timeout> ] "
#    . "[ --ignoressl ] "
    . "[ -h|--help ] ",
    version => '0.1',
    blurb   => 'Nagios plugin to check Wifiplugs and attached sensors running Tasmota Firmware',
    extra   => "\nExample: \n"
    . "check_tasmota.pl --url http://192.168.178.10 -U youruser -P yourpassword"
    . "              -D Power --warning :5 --critical :10 "
    . "check_tasmota.pl --url http://192.168.178.10 -U youruser -P yourpassword"
    . "              -D ENERGY -S Power --warning :5 --critical :10 ",
    url     => 'http://www.creativeit.eu/software/nagios-plugins/check-tasmota.html',
    plugin  => 'check_tasmota',
    timeout => 15,
    shortname => "CheckTasmota"
);

# add valid command line options and build them into your usage/help documentation.

$np->add_arg(
    spec => 'url|u=s',
    help => '-u, --url http://192.168.178.10',
    required => 1,
);

$np->add_arg(
    spec => 'Password|P=s',
    help => '-P, --Password',
    required => 0,
);

$np->add_arg(
    spec => 'SensorDevice|D=s',
    help => '-D, --SensorDevice Power|ENERGY',
    required => 1,
);

$np->add_arg(
    spec => 'Sensor|S=s',
    help => '-S, --Sensor ',
    default => 0,
    required => 0,
);

$np->add_arg(
    spec => 'warning|w=s',
    help => '-w, --warning INTEGER:INTEGER . See '
    . 'http://nagiosplug.sourceforge.net/developer-guidelines.html#THRESHOLDFORMAT '
    . 'for the threshold format. ',
);

$np->add_arg(
    spec => 'critical|c=s',
    help => '-c, --critical INTEGER:INTEGER . See '
    . 'http://nagiosplug.sourceforge.net/developer-guidelines.html#THRESHOLDFORMAT '
    . 'for the threshold format. ',
);

#$np->add_arg(
#    spec => 'ignoressl',
#    help => "--ignoressl\n   Ignore bad ssl certificates",
#);


####  Parse @ARGV and process standard arguments (e.g. usage, help, version)
$np->getopts;

my $opt_pass = $np->opts->Password;
my $opt_device = $np->opts->SensorDevice;
my $opt_sensor = $np->opts->Sensor;

if ($np->opts->verbose) { print "Verbose: Nagios Object \n"; print Dumper ($np);  print "#----\n" };


#### ----------- Useragent -----------

my $ua = LWP::UserAgent->new;
my $cookies = HTTP::Cookies->new( );

$ua->env_proxy;
$ua->cookie_jar( $cookies );
$ua->agent('check_tasmota/1.0');
$ua->default_header('Accept' => 'application/json');
$ua->protocols_allowed( [ 'http' ] );
$ua->parse_head(0);
$ua->timeout($np->opts->timeout);

#if ($np->opts->ignoressl) {
#    $ua->ssl_opts(verify_hostname => 0, SSL_verify_mode => 0x00);
#}

if ($np->opts->verbose) { print "Verbose: Useragent \n"; print Dumper ($ua);  print "#----\n" };


#### ----------- Data -----------

## Build Data URL

my $urlp = $np->opts->url .  "/cm?cmnd=COMMAND";

# Check, if just Power is requested, or an attached sensor
if (uc($opt_device) eq "POWER") {
    # http://192.168.18.201/cm?cmnd=Power
	my $cmnd1 = "COMMAND"; 
	my $cmnd2 = "Power";
	$urlp =~ s/$cmnd1/$cmnd2/g;
} else {
	# http://192.168.18.201/cm?cmnd=Status%208
	my $cmnd1 = "COMMAND" ;
	my $cmnd2 = "Status%208";
	$urlp =~ s/$cmnd1/$cmnd2/g;
}

# Add auth, if Password is set
my $url = $urlp;
if ($opt_pass) {
	my $auth1 = "//";
	my $auth2 = "//admin:" . $opt_pass . "@";
	$url = $urlp =~ s/$auth1/$auth2/g;
} 

# verbose
if ($np->opts->verbose) { print "Verbose: Data Url : " . $url . "\n#----\n" };


## Get Data Response
my $response = $ua->request(GET $url, 'Content-type' => 'application/json');

if (not $response->is_success) {
    $np->nagios_exit(CRITICAL, "Connection to " . $urlp . " failed: ".$response->status_line);
}

# verbose
#if ($np->opts->verbose) { print "Verbose: Data Response \n"; print Dumper ($response);  print "#----\n" };


#### ----------- Parse -----------

## Parse JSON
my $json_response = decode_json($response->content);
if ($np->opts->verbose) { print "Verbose: JSON Response \n"; print Dumper ($json_response);  print "#----\n"};


## Compute value and limits
my @warning = split(',', $np->opts->warning);
my @critical = split(',', $np->opts->critical);


## Value depends on commandclass
my $check_value;
my $check_title;
my $check_probe;
my $check_value_tmp;
my $check_scale;
#my $jsonxs = new JSON::XS;

if (uc($opt_device) eq "POWER") {

	## Just gettin Power stats
    if ($np->opts->verbose) { print "Verbose: Parsing power state \n"};
	
	$check_value_tmp = $json_response->{'POWER'};
    if ($check_value_tmp eq "ON")
      { $check_value = 1  }
    elsif ($check_value_tmp eq "OFF")
      { $check_value = 0  }
    else         
      { $check_value = -1 }

    $check_title = "OnOff";
    $check_probe = "OnOff";
    $check_scale = "";

	if ($np->opts->verbose) { 
		print "Verbose: Result for power state " . $check_value_tmp . "\n";
		print "Verbose:                returns " . $check_value . "\n";
		print "#----\n";
	}
    
} else {
 	
	switch ($opt_sensor) {
	
		### AM2301, ...
		case "Temperature" { 
            ## Sensor - Temperature
			if ($np->opts->verbose) { print "Verbose: Parsing Sensor " . $opt_device ." for " . $opt_sensor ."\n#----\n"};
 
            $check_value = $json_response->{'StatusSNS'}->{uc($opt_device)}->{'Temperature'};
            $check_title = "Temperatur";
            $check_probe = "Temperatur";
		    $check_scale = "°" . $json_response->{'StatusSNS'}->{'TempUnit'};
		}
		  
		case "Humidity" { 
            ## Sensor - Humidity
			if ($np->opts->verbose) { print "Verbose: Parsing Sensor " . $opt_device ." for " . $opt_sensor ."\n#----\n"};
 
            $check_value = $json_response->{'StatusSNS'}->{uc($opt_device)}->{'Humidity'};
            $check_title = "Humidity";
            $check_probe = "Humidity";
		    $check_scale = "%";
		}

		
		### POW - ENERGY
		# "StatusSNS":{"Time":"2018-05-12T19:04:19",
		#              "ENERGY":{"Total":0.000,"Yesterday":0.000,"Today":0.000,"Power":0,"Factor":0.00,"Voltage":230,"Current":0.000}
		#             }
		case "Total" { 
            ## ENERGY - Total
			if ($np->opts->verbose) { print "Verbose: Parsing Sensor " . $opt_device ." for " . $opt_sensor ."\n#----\n"};
 
            $check_value = $json_response->{'StatusSNS'}->{uc($opt_device)}->{'Total'};
            $check_title = "Energy total";
            $check_probe = "Energy total";
		    $check_scale = "kWh";
		}
		case "Yesterday" { 
            ## ENERGY - Yesterday
			if ($np->opts->verbose) { print "Verbose: Parsing Sensor " . $opt_device ." for " . $opt_sensor ."\n#----\n"};
 
            $check_value = $json_response->{'StatusSNS'}->{uc($opt_device)}->{'Yesterday'};
            $check_title = "Energy Yesterday";
            $check_probe = "Energy Yesterday";
		    $check_scale = "kWh";
		}
		case "Today" { 
            ## ENERGY - Today
			if ($np->opts->verbose) { print "Verbose: Parsing Sensor " . $opt_device ." for " . $opt_sensor ."\n#----\n"};
 
            $check_value = $json_response->{'StatusSNS'}->{uc($opt_device)}->{'Today'};
            $check_title = "Energy Today";
            $check_probe = "Energy Today";
		    $check_scale = "kWh";
		}
		case "Voltage" { 
            ## ENERGY - Voltage
			if ($np->opts->verbose) { print "Verbose: Parsing Sensor " . $opt_device ." for " . $opt_sensor ."\n#----\n"};
 
            $check_value = $json_response->{'StatusSNS'}->{uc($opt_device)}->{'Voltage'};
            $check_title = "Voltage";
            $check_probe = "Voltage";
		    $check_scale = "V";
		}
		case "Current" { 
            ## ENERGY - Current
			if ($np->opts->verbose) { print "Verbose: Parsing Sensor " . $opt_device ." for " . $opt_sensor ."\n#----\n"};
 
            $check_value = $json_response->{'StatusSNS'}->{uc($opt_device)}->{'Current'};
            $check_title = "Current";
            $check_probe = "Current";
		    $check_scale = "A";
		}

		
		### not implemented
		else { 
			if ($np->opts->verbose) { print "Verbose: Parsing Sensor " . $opt_sensor . " on SensorDevice " . $opt_device ."\n#----\n"};
			$check_value = -1;
			$check_title = "Sensor " . $opt_sensor . " on SensorDevice " . $opt_device . " is not supported";
			$check_probe = "Sensor " . $opt_sensor . " on SensorDevice " . $opt_device . " is not supported";
			$check_scale = "";
          }
	}
}

# Check if scale is an allowed value [[u|m]s % B c}]
my $check_scale_in_list = 0;
if ($check_scale eq "°C" ) { $check_scale_in_list = 1; }
if ($check_scale eq "°K" ) { $check_scale_in_list = 1; }
if ($check_scale eq "A") { $check_scale_in_list = 1; }
if ($check_scale eq "V") { $check_scale_in_list = 1; }
if ($check_scale eq "W" ) { $check_scale_in_list = 1; }
if ($check_scale eq "kWh") { $check_scale_in_list = 1; }
if ($check_scale eq "%" ) { $check_scale_in_list = 1; }

# Check value against thresholds...
my $result = -1;
$result = $np->check_threshold(
    check => $check_value,
    warning => $np->opts->warning,
    critical => $np->opts->critical
 );

if ($np->opts->verbose) { 
	print "Verbose: Value $check_value "; 
	print "\n         Scale $check_scale"; 
	print "\n         Title $check_title"; 
	print "\n         Probe $check_probe"; 
	print "\n#----\n"
};


#### Compute value and limits

my @statusmsg;

if ($check_scale_in_list eq 1) {
	push(@statusmsg, "$check_probe: ".$check_value.$check_scale);
	$np->add_perfdata(
		label => $check_title,
		value => $check_value,
		uom => $check_scale, 
		threshold => $np->set_thresholds( warning => $np->opts->warning, critical => $np->opts->critical),
	); 
} else {
	push(@statusmsg, "$check_probe: ".$check_value);
	$np->add_perfdata(
		label => $check_title . "(" . $check_scale . ")",
		value => $check_value,
		threshold => $np->set_thresholds( warning => $np->opts->warning, critical => $np->opts->critical),
	); 
};

if ($np->opts->verbose) { print "Verbose: StatusMsg"; print Dumper (@statusmsg);  print "#----\n"};


#### Finally

$np->nagios_exit(
    return_code => $result,
    message     => join(', ', @statusmsg),
);
