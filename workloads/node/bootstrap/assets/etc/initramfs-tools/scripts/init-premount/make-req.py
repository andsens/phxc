import dhcppython
from textwrap import wrap

print('\n'.join(wrap(dhcppython.packet.DHCPPacket.Request(
  mac_addr='5e:bb:f6:9e:ee:fa',
  seconds=0,
  tx_id=1111111,
  option_list=[
    dhcppython.options.VendorClassIdentifier(code=60, length=len(b'PXEClient:home-cluster'), data=b'PXEClient:home-cluster')
  ]
).asbytes.hex(),32)))
