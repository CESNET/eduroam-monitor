# ipsec-ping

A tool to draw simple graphs of IPsec reliability. The tool heavily depends on our configuration data stored in LDAP, we doubt about portability into other NRENs.

![example ipsec-ping output](https://github.com/CESNET/eduroam-monitor/blob/master/ipsec_ping/docs/example.png?raw=true)

IPsec endpoint (NREN level RADIUS server) periodically executes script [eduroam_ping.sh](https://github.com/CESNET/eduroam-monitor/blob/master/ipsec_ping/eduroam_ping.sh) which reads existing SA (by using `setkey -DP`) and pings to all its peers. The output of `ping` command is fed into `logger` with priority `local5.info`.

Logs are transported by `syslog-ng` to another host for processing:

```syslog-ng config
destination eduRoamPing { 
        file("/var/log/eduRoamPing-$YEAR-$MONTH-$DAY" owner("root") group("adm") perm(0640));
        udp("ermon.cesnet.cz" port(514) persist-name("ermon3"));
};

filter f_eduroamping { facility(local5); };

log { source(src); filter(f_eduroamping); destination(eduRoamPing); };
```

Data are received on another host:

```syslog-ng config
source s_udp { udp(); };

destination eduroam_ping { file("/var/log/radius1edu-ping-$YEAR-$MONTH-$DAY" owner("root") group("adm") perm(0640)); };

filter f_eduroam_ping { facility(local5); };

log { source(s_udp); filter(f_eduroam_ping); destination(eduroam_ping); };
```

and finally processed by script [ipsec-ping.pl](https://github.com/CESNET/eduroam-monitor/blob/master/ipsec_ping/ipsec-ping.pl) as `./ipsec-ping.pl --CFGFilename ./ipsec-ping.cfg`. Example of config file is [provided](ipsec-ping.cfg).

In past we were providing also info about restarts of `racoon` daemon, this functionality was partially provided by [racoonRestarts.pl](https://github.com/CESNET/eduroam-monitor/blob/master/ipsec_ping/racoonRestarts.pl) script. This functionality is not available any more.
