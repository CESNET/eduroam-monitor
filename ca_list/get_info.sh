#!/bin/bash
# ========================================================================================
# generate list of organizations and the current EAP certs
# output as a web page?
# ========================================================================================








# ========================================================================================
# main func
# ========================================================================================
function main2()
{
  # prochazet realmy v db ldap_to_icinga
  # -> objevi se i "neevidovane" realmy - guest.cesnet.cz
  # na zaklade realmu vybrat radius server

  # kazdy alias realmu muze mit vlastni (ruzny!) certifikat pro eap
  


















  # vyuzit eap_cert_db
  # iterovat nad vsemi *pem soubory

  path="/var/lib/nagios/eap_cert_db/"
  coverage_path="/home/eduroamdb/eduroam-db/web/coverage/coverage_files/"


  # v tomto pripade by se mohl grepovat realm v cilovem souboru a pripadne by se tam nemusel pridavat
  # ale co zmeny certifikatu?  

  > /tmp/cert_db_data.txt


  # TODO - jak to dopadne s linky na certifikaty?
  for i in $path*eap.pem
  do
    # get realm from eap cert filename
    realm=$(basename $i | sed 's/_.*$//g')

    # get org name from coverage info
    org=$(grep "\"$realm\"" /home/eduroamdb/eduroam-db/web/coverage/config/realm_to_inst.js | cut -d ":" -f2 | tr -d '" ,')

    # TODO - neni k dispozici organizace, data nepublikujeme?
    if [[ -z "$org" ]]
    then
      continue
    fi

    cert_size=$(du -b $i | awk '{ print $1 }')

    # check if file is at least 1000 bytes (not empty or somehow malformed)
    # TODO some better check may be usefull
    if [[ $cert_size -lt 1000 ]]
    then
      continue
    fi

    # no coverage info exists
    if [[ ! -e "$coverage_path/$org.json" ]]
    then
      continue
    fi

    # get cert issuer
    cert=$(openssl x509 -nameopt utf8 -in $i -noout -issuer | sed 's/issuer=//g' | tr -d "\n")

    # get realm and aliases
    realm_list=$(jq -c '.inst_realm' "$coverage_path/$org.json" | tr -d '["]')

    # TODO - check if URL is available
    url=$(jq '.info_URL[0].data' "$coverage_path/$org.json" | tr -d '"')
    org_name=$(jq '.inst_name[0].data' "$coverage_path/$org.json" | tr -d '"')

    # TODO - proper db access
    # get list of servers
    servers=$(mysql -e "select distinct(radius_cn) from radius_server where inf_realm=\"cn=$realm,ou=realms,o=eduroam,o=apps,dc=cesnet,dc=cz\";" ldap_to_icinga | tail -n +2 | tr "\n" "," | sed 's/,$//g')

    echo "$url,$org_name;$realm_list;$cert;$servers"
  done

  
}
# ========================================================================================





# ========================================================================================
# main func
# ========================================================================================
function main()
{
  # data from icingacli
  data=$(icingacli monitoring list services --host=radius1.cesnet.cz --service=@* --format=json --columns=service_description,service_state,service_long_output)

  # debug
  #data=$(icingacli monitoring list services --host=radius1.cesnet.cz --service=@cesnet.cz --format=json --columns=service_description,service_state,service_long_output)

  # TODO - budeme chtit fitrovat takove, ktere jsou aktualne critical?

  # service description (realm) and cert info
  info=$(echo -e $data | jq -c '.[] | select(.service_state == "0") | [.service_description, .service_long_output]')


  #echo -e "$info"

  #echo -e "$info" | sed 's/^\["@//g; s/\]//g' | 



  # tohle nebude fungovat dobre spolu s filtrovanim critickych
  > /tmp/cert_db_data.txt
  
  # out structure:
  # realm;issuer
  #out=$(
    # process info line by line
    while read -r line
    do
      echo -e "$line" | python3 -c 'import sys; import lxml.objectify; f = sys.stdin.read(); realm = f.split(",")[0].replace("[\"@", "").replace("\"",""); issuer = f.split("\n")[2].replace("Issuer: ","") ; print(realm + ";" + issuer)'
    done < <(echo "$info") >> /tmp/cert_db_data.txt
  #)

  

  
}
# ========================================================================================
#main
main2
