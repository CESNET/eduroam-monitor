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

lines = sys.stdin.readlines()

print("<html>")
print("<head>")
print('<meta charset="UTF-8">')
print("</head>")
print("<table>")

print("<tr>")
print("<th>organizace</th>")
print("<th>realmy</th>")
print("<th>použitá CA</th>")
print("<th>jména RADIUS serverů</th>")
print("</tr>")


for line in lines:
  input_array = line.split(";")

  print("<tr>")

  # org name
  print('<th><a href="' + input_array[0].split(",")[0] + '">' + ",".join(input_array[0].split(",")[1:]) + '</a></th>')

  # realms
  realms = input_array[1].split(",")
  print('<th>')

  for i in realms:
    # TODO - add newline to table
    print('@' + i)

  print('</th>')
    

  # cert info, use only CN field
  cert_info = input_array[2].split(",")

  for i in cert_info:
    if "CN=" in i:
      ca_name = re.sub("^\s*", "", i).replace("CN=", "")    # remove empty characters at the beginning and remove 'CN='
      if ca_name in cert_db.db:
        print('<th><a href="' + cert_db.db[ca_name] + '">' + ca_name + '</a></th>')
      else:
        print('<th>' + ca_name + '</th>')
      break

  # radius servers
  radius_servers = input_array[3].split(",")
  print('<th>')

  for i in radius_servers:
    # TODO - add newline to table
    print(i)

  print('</th>')


  print("</tr>")


print("</html>")
