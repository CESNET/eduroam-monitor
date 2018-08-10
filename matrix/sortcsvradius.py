#!/usr/bin/env python3

import csv
import sys


def decorate_domain(d):
    return ".".join(reversed(d.split(".")))


def keyfunc(row):
    """ Return key for for hostname and service description
        for:
        ["proxy.exmaple.com", "@example.org"]
        return:
        ("com.example.proxy", "org.example")
    """
    return (decorate_domain(row[0]), decorate_domain(row[1][1:]))


reader = csv.reader(sys.stdin)
writer = csv.writer(sys.stdout)
for row in sorted(reader, key=keyfunc):
    writer.writerow(row)
