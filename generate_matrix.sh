#!/bin/bash

{ echo "host_name,service_description,service_state,service_last_check" ; icingacli monitoring list services --service="*@*" --format='$host_name$,$service_description$,$service_state$,$service_last_check$' --columns=host_name,service_state,service_description,service_last_check | /var/www/eduroam-monitor/sortcsvradius.py ; } | jq -R -s -f /var/www/eduroam-monitor/filter.jq -c -r > /var/www/eduroam-monitor/matrix/data.json
