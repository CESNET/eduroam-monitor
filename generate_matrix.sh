#!/bin/bash
{ echo "host_name,service_state,service_description" ; icingacli monitoring list services --service="*@*" --format='$host_name$,$service_state$,$service_description$' --columns=host_name,service_state,service_description | sort -k 3,1  ; } | jq -R -s -f filter.jq -c -r > matrix/data.json
