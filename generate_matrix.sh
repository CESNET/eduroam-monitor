#!/bin/bash

{ echo "host_name,service_state,service_description,service_last_check" ; icingacli monitoring list services --service="*@*" --format='$host_name$,$service_state$,$service_description$,$service_last_check$' --columns=host_name,service_state,service_description,service_last_check | sort -k 3,1  ; } | jq -R -s -f /var/www/eduroam-monitor/filter.jq -c -r > /var/www/eduroam-monitor/matrix/data.json
