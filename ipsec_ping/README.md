# ipsec-ping

A tool to draw simple graphs of IPsec reliability. The tool heavily depends on our configuration data stored in LDAP, we doubt about portability into other NREN.

![example ipsec-ping output](https://github.com/CESNET/eduroam-monitor/blob/master/ipsec_ping/docs/example.png?raw=true =300x)

On IPsec endpoint (NREN level RADIUS server) is periodically executed script [eduroam_ping.sh]() which reads existing SA (by using `setkey -DP`) and ping to all its peers. The output of `ping` command is feed into `logger` with `local5.info` priority. 

Logs are transported by `syslog-ng` to another host for processing:

```syslog-ng config
destination eduRoamPing { 
        file("/var/log/eduRoamPing-$YEAR-$MONTH-$DAY" owner("root") group("adm") perm(0640));
        udp("ermon.cesnet.cz" port(514) persist-name("ermon3"));
};

filter f_eduroamping { facility(local5); };

log { source(src); filter(f_eduroamping); destination(eduRoamPing); };
```

data is received on another host:

```syslog-ng config
source s_udp { udp(); };

destination eduroam_ping { file("/var/log/radius1edu-ping-$YEAR-$MONTH-$DAY" owner("root") group("adm") perm(0640)); };

filter f_eduroam_ping { facility(local5); };

log { source(s_udp); filter(f_eduroam_ping); destination(eduroam_ping); };
```

and finally processed by script [ipsec-ping.pl]() `./ipsec-ping.pl --CFGFilename ./ipsec-ping.cfg` example of config file is [provied](ipsec-ping.cfg). 

In past we were providing also info about restarts of `racoon` daemon, this functionality was partially provided by [racoonRestarts.pl]() script. The part from IPsec endpoint is lost.