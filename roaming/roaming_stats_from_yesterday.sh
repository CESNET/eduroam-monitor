#!/bin/bash

YESTERDAY=`date +"%Y-%m-%d" -d "1 day ago"`
LOGFILE=`ls -1 /var/log/radius1edu-radius-$YESTERDAY*`

/home/roaming/roaming_stats.pl --CFGFilename=/home/roaming/roaming_stats.cfg \
			       --LogFile=$LOGFILE \
			       --RebuildGraphs=1
