#!/bin/bash
# =================================================================================
# this script generates source data for eduroam availability matrix
# it is intended to be run by cron at regular intervals
# =================================================================================

{
  echo "host_name,service_description,service_state,service_state_type,service_last_check" ;       # add csv header
  icingacli monitoring list services --service="@*" --format='$host_name$,$service_description$,$service_state$,$service_state_type$,$service_last_check$' --columns=host_name,service_state,service_description,service_last_check,service_state_type |  # get data
  /var/www/eduroam-monitor/matrix/sortcsvradius.py ;                                   # sort domains
} |
  jq -R -s -f /var/www/eduroam-monitor/matrix/filter.jq -c -r > /var/www/eduroam-monitor/matrix/html/data.json      # convert to json & output to file
