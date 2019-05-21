#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ==============================================================================
# create web page with into about organizations connected to eduroam
# org name, realm list, cert info, radius servers
# ==============================================================================
import sys
import re
import cert_db
# ==============================================================================
# main function
# ==============================================================================
def main():
  lines = sys.stdin.readlines()

  # table header
  print("^ organizace ^ realmy ^ použitá CA ^ jména RADIUS serverů ^")

  for line in lines:
    input_array = line.split(";")

    # org name
    org_name = '[[' + input_array[0].split(",")[0] + '|' + ",".join(input_array[0].split(",")[1:]) + ']]'

    # realms
    realms = ", ".join(["@" + i for i in input_array[1].split(",")])

    # cert info, use only CN field
    cert_info = input_array[2].split(",")

    for i in cert_info:
      if "CN=" in i:
        ca_name = re.sub("^\s*", "", i).replace("CN=", "")    # remove empty characters at the beginning and remove 'CN='
        if ca_name in cert_db.db:
          cert_info = '[[' + cert_db.db[ca_name] + '|' + ca_name + ']]'
        else:
          cert_info = ca_name
        break

    # radius servers
    radius_servers = input_array[3].replace('\n', '').replace(",", ", ")

    # final output
    print('| ' + org_name + ' | ' + realms + ' | ' + cert_info + ' | ' + radius_servers + ' |')

# ==============================================================================
# program is run directly, not included
# ==============================================================================
if __name__ == "__main__":
  main()

