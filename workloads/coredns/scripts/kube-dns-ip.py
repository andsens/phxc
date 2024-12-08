#!/usr/bin/env python3
import ipaddress, sys
cidr = sys.argv[1]
if len(cidr.split('.')) == 4: print(ipaddress.IPv4Network(cidr)[10])
else: print(ipaddress.IPv6Network(cidr)[10])
