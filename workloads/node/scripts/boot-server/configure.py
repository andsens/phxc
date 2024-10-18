import base64, logging, secrets, uuid, sys
import questionary
from .registry import Registry
from . import ErrorMessage, NodeState, NodeConfig, BlockDevice

log = logging.getLogger(__name__)

async def configure_nodes(registry: Registry, machine_id: uuid.UUID | None = None):
  if machine_id is None:
    all_machines = map(lambda m: (m, registry.get_node_state(m), registry.get_node_config(m)), registry.get_all_machine_ids())
    selection: tuple[uuid.UUID, NodeState, NodeConfig] = await questionary.select(
      "Please select the machine you would like to configure:", [
        questionary.Choice(f'{state.variant} {machine_id} ({'unconfigured' if config is None else 'configured'})',
                          value=(machine_id, state, config))
        for machine_id, state, config in all_machines
      ]
    ).ask_async()
    if selection is None:
      raise ErrorMessage('You must select an IP for the boot-server to listen on')
    (machine_id, state, config) = selection
  else:
    state = registry.get_node_state(machine_id)
    config = registry.get_node_config(machine_id)

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
  registry.update_node_config(machine_id, config)
  return config
