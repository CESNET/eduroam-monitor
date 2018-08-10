# radiator munin plugin

A Simple plugin for [munin](http://munin-monitoring.org/) to monitor radiator activity. Example output:
![example radiator_munin output](https://github.com/CESNET/eduroam-monitor/blob/master/radiator_munin/docs/example.png?raw=true)

[Radiator](https://www.open.com.au/radiator/) RADIUS server supports reporting number of processed packets by SNMP, 
first you need to configure it to listen on SNMP port:
```radius.cfg
<SNMPAgent>     
        BindAddress 192.1.2.3
        ROCommunity super-secret
        Managers localhost 127.0.0.1
</SNMPAgent>
```
Next you need to download plugin [radiator]() into `/usr/local/bin/radiator`, create symlinks in directory `/etc/munin/plugins`:
```bash
root@radius:/etc/munin/plugins# ln -s /usr/local/bin/radiator radiator_high
root@radius:/etc/munin/plugins# ln -s /usr/local/bin/radiator radiator_medium
root@radius:/etc/munin/plugins# ln -s /usr/local/bin/radiator radiator_low
```
Radiator stats are divided into three groups high - medium - low acording volume of packets on EAP proxy RADIUS server. There is usualy 10 times more Access-Request packets than Access-Accept.

And finaly you need setup your RO SNMP Comunity:
```text
root@radius1mng4:# cat /etc/munin/plugin-conf.d/radiator
[radiator*]
env.SNMP_SERVER         192.1.2.3
env.SNMP_COMUNITY       super-secret
```

