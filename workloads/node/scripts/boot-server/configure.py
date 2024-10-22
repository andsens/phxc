'''configure-node
Usage:
  configure-node -b IP -p PATH -c PATH [<MACHINE-ID>]

Options:
  -b --boot-server-ip IP   IP of the boot-server
  -p --admin-privkey PATH  Path to the admin private key file
  -c --cafile PATH         Path to the home-cluster root certificate
'''

import asyncio, base64, ipaddress, json, logging, secrets, ssl, sys, time, uuid
import urllib.request
from pathlib import Path
import docopt, questionary, jwt
from . import AnyIPAddress, ErrorMessage, NodeState, NodeConfig, BlockDevice

log = logging.getLogger(__name__)

async def main():
  params = docopt.docopt(__doc__)
  boot_server_ip = ipaddress.ip_address(params['--boot-server-ip'])
  admin_privkey = Path(params['--admin-privkey'])
  cafile = Path(params['--cafile'])

  client = RegistryClient(boot_server_ip, admin_privkey, cafile)
  if params['<MACHINE-ID>'] is None:
    all_machines = [(m, client.get_node_state(m), client.get_node_config(m)) for m in client.get_all_machine_ids()]
    if len(all_machines) == 0:
      raise ErrorMessage('No machines have reported their state to the boot-server yet')
    selection: tuple[uuid.UUID, NodeState, NodeConfig] = await questionary.select(
      "Please select the machine you would like to configure:", [
        questionary.Choice(f'{state['variant']} {machine_id} ({'unconfigured' if config is None else 'configured'})',
                          value=(machine_id, state, config))
        for machine_id, state, config in all_machines
      ]
    ).ask_async()
    if selection is None:
      raise ErrorMessage('You must select an IP for the boot-server to listen on')
    (machine_id, state, config) = selection
  else:
    machine_id = uuid.UUID(params['<MACHINE-ID>'])
    state = client.get_node_state(machine_id)
    config = client.get_node_config(machine_id)

  if state is None:
    raise ErrorMessage(f'The node {machine_id} has not reported any state yet, unable to configure it')

  if len(state['blockdevices']) == 0:
    raise ErrorMessage(f'The node {machine_id} does not have any blockdevices')

  if config is None:
    config = {}

  node_label_choices = ['node-role.kubernetes.io/control-plane=true']

  while True:
    config['disk'] = config.get('disk', {})
    if config['disk'].get('encryption-key', None) is None:
      log.info('Generating disk encryption key')
      config['disk'] = config.get('disk', {})
      config['disk']['encryption-key'] = base64.b64encode(secrets.token_bytes(128)).decode()

    config['hostname'] = await questionary.text('Enter a hostname for the node (must not contain dots)', default=config.get('hostname', ''),
                                                validate=lambda n: '.' not in n).ask_async()
    config['node-label'] = await questionary.checkbox('Toggle any node labels you want to apply',
      choices=[
        questionary.Choice(label, checked=label in config.get('node-label', []))
        for label in node_label_choices
      ]
      ).ask_async()
    while True:
      blockdevice: BlockDevice = await questionary.select(
        'Select boot- and datadisk',
        choices=[
          questionary.Choice(f'{bd['devpath']}: {bd['filesystem'] if bd['filesystem'] is not None else ('partitioned' if bd['partitions'] is not None else 'blank')}', value=bd)
          for bd in state['blockdevices']
        ], default=None if config['disk'].get('devpath', None) is None else next(bd for bd in state['blockdevices'] if bd['devpath'] == config['disk']['devpath'])
      ).ask_async()
      if blockdevice['filesystem'] is not None or blockdevice['partitions'] is not None:
        log.warning('ATTENTION: You have selected a disk with an existing filesystem or partition. Doing this will wipe all data on that disk.')
        if await questionary.confirm('Are you sure you want to continue', default=False).ask_async():
          config['disk']['force'] = True
          config['disk']['devpath'] = blockdevice['devpath']
          break
      else:
        config['disk']['devpath'] = blockdevice['devpath']
        break

    config['networks'] = config.get('networks', {})
    while True:
      nic_choices = []
      for nic in state['nics']:
        net = next(filter(lambda net: net[1]['mac'] == nic['mac'], config['networks'].items()), None)
        nic_state = 'unconfigured' if net is None else f'configured as {net[0]}'
        nic_choices.append(questionary.Choice(f'{nic['ifname']}: {nic['mac']} ({nic_state})', value=nic))
      nic_choices.append(questionary.Choice('Done'))
      configure_nic = await questionary.select('Select network interface to configure', choices=nic_choices, default='Done').ask_async()
      if configure_nic == 'Done':
        break
      current_net = next(filter(lambda net: net[1]['mac'] == nic['mac'], config['networks'].items()), None)
      if current_net is not None:
        del config['networks'][current_net[0]]

      net_name = await questionary.text('Enter a name for the network (e.g. primary, lan0, host)',
                                        default=current_net[0] if current_net is not None else '').ask_async()
      net_mode = await questionary.select('Select how the network should be configure', choices=['DHCP', 'Fixed IP(s)'],
                                          default=None if current_net is None else ('DHCP' if current_net[1]['dhcp'] else 'Fixed IP(s)')).ask_async()
      if net_mode == 'DHCP':
        config['networks'][net_name] = {
          'mac': nic['mac'],
          'dhcp': True
        }
      else:
        net_fixed_ips = await questionary.text('Enter the IPs (one per line) you wish to assigned (append the prefix length, /32 for IPv4, /128 for IPv6)',
                                               default='' if current_net is None or current_net[1]['dhcp'] else '\n'.join(current_net[1]['static']),
                                               multiline=True).ask_async()
        config['networks'][net_name] = {
          'mac': nic['mac'],
          'dhcp': False,
          'static': net_fixed_ips.split('\n')
        }
    if await questionary.confirm('Would you like to save the node configuration?', default=False).ask_async():
      break
  client.update_node_config(machine_id, config)
  return config


class RegistryClient:

  boot_server_ip: AnyIPAddress
  jwk: str
  ctx: ssl.SSLContext

  def __init__(self, boot_server_ip: AnyIPAddress, admin_privkey: Path, cafile: Path):
    self.boot_server_ip = boot_server_ip
    with admin_privkey.open('r') as h:
      self.jwk = h.read()
    self.ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    self.ctx.load_verify_locations(cafile=cafile)
    self.ctx.check_hostname = False

  def get_all_machine_ids(self) -> list[uuid.UUID]:
    return map(lambda id: uuid.UUID(id), self.api_call('GET', f'machine-ids'))

  def get_node_config(self, machine_id: uuid.UUID) -> NodeConfig | None:
    return self.api_call('GET', f'config/{machine_id}')

  def update_node_config(self, machine_id: uuid.UUID, config: NodeConfig):
    return self.api_call('PUT', f'config/{machine_id}', config)

  def get_node_state(self, machine_id: uuid.UUID) -> NodeState | None:
    return self.api_call('GET', f'state/{machine_id}')

  def api_call(self, method: str, path: str, body: None | dict = None) -> dict | None:
    token = jwt.encode(key=self.jwk, algorithm='ES256', payload={
      'sub': f'{method} {path}',
      'iss': 'admin',
      'aud': 'boot-server',
      'jti': secrets.token_bytes(20).hex(),
      'nbf': int(time.time() - 30),
      'exp': int(time.time() + 30),
    })
    headers = {
      'Host': 'boot-server.node.svc.cluster.local',
      'Authorization': f'Bearer {token}',
    }
    data = None
    if body is not None:
      headers['Content-Type'] = 'application/json'
      data = json.dumps(body).encode()
    req = urllib.request.Request(url=f'https://{self.boot_server_ip}:8020/{path}',
                                 headers=headers, method=method, data=data)
    try:
      with urllib.request.urlopen(req, context=self.ctx) as f:
        return json.loads(f.read().decode())
    except urllib.error.HTTPError as e:
      if e.code == 404:
        return None
      else:
        raise

if __name__ == "__main__":
  try:
    asyncio.run(main())
  except KeyboardInterrupt as e:
    pass
  except ErrorMessage as e:
    sys.stderr.write(f'{e}\n')
