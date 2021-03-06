# availability matrix

The availability matrix is actually "only" a visualisation of monitoring data. The original matrix has been created in ~ 2006 and has been used since.
There were several reasons which made is really useful. The main reason was to get complete overview of all the testing users on all the servers in simple graph,
which could help easily diagnose problematic servers or realms and could also help diagnose some more complex problems.

Screenshot from original matrix below.

![Screenshot](https://raw.githubusercontent.com/CESNET/eduroam-monitor/master/matrix/orig_matrix.png "original matrix")

## new setup

It was decided that this should be preserved with the new monitoring setup. Original matrix was taken as a model.

![Screenshot](https://raw.githubusercontent.com/CESNET/eduroam-monitor/master/matrix/new_matrix.png "new matrix")

## how it works

The matrix source data are generated by [generate_matrix.sh](https://github.com/CESNET/eduroam-monitor/blob/master/matrix/generate_matrix.sh)
The actual data source is `icingacli` tool. 
The script uses simple [python script](https://github.com/CESNET/eduroam-monitor/blob/master/matrix/sortcsvradius.py) for domain sorting and
`jq` for final transformation into json format. Script execution is setup in a cronjob, so the data are recreated in regular intervals.
The main script is ran by cron every 2 minutes.


The web part is done in d3.js because of previous expirience with it.
Using d3.js made the new matrix loading fast and browers also deal with it well in other aspects.
The web page itself is a statical html page, so everything is done in javascript.
The graph is created by [main.js](https://github.com/CESNET/eduroam-monitor/blob/master/matrix/html/main.js).
The data are refreshed every 60 seconds.

## Deployment video

This is how availability matrix looked like when the new monitoring system of czech eduroam was put into the operation.

### Czech version
[![Czech version](https://img.youtube.com/vi/R-8_SS2_XYY/0.jpg)](https://www.youtube.com/watch?v=R-8_SS2_XYY)

### English version
[![English version](https://img.youtube.com/vi/7Ll8rHvmR8s/0.jpg)](https://www.youtube.com/watch?v=7Ll8rHvmR8s)
