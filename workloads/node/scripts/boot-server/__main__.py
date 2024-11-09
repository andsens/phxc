'''boot-server
Usage:
  boot-server HOST_IP ETCD_URL
'''

import asyncio, ipaddress, logging, os, signal, sys
from pathlib import Path
import docopt
from . import __name__ as root_name, ErrorMessage, Context, NodeState
from .dhcp_proxy import dhcp_proxy
from .api import api
from .tftpd import tftpd
import ifaddr, logfmter, questionary
from .node import Node
from kubernetes_asyncio import config
import logging
from pathlib import Path
import uuid, json
from .watch_nodes import watch_nodes
import macaddress

log = logging.getLogger(root_name)

async def main():
  params = docopt.docopt(__doc__) # type: ignore
  setup_logging()

  shutdown_event = asyncio.Event()
  loop = asyncio.get_running_loop()
  loop.add_signal_handler(signal.SIGINT, lambda: shutdown_event.set())
  loop.add_signal_handler(signal.SIGTERM, lambda: shutdown_event.set())

  host_ip = ipaddress.ip_address(params['HOST_IP'])
  if not isinstance(host_ip, ipaddress.IPv4Address):
    raise Exception('HOST_IP must be an IPv4 address')

  ctx = Context(host_ip, params['ETCD_URL'], shutdown_event)

  await config.load_kube_config()

  if params['--import'] is not None:
    log.info('Updating state, config, and authn-key of host node')
    import_path = Path(params['--import'])
    host_state: NodeState = json.loads((import_path / 'node-state.json').read_text())
    host_node = \
      Node.get_by_machine_id(ctx, uuid.UUID((import_path / 'machine-id').read_text())) or \
      Node.new_by_mac(ctx, macaddress.MAC(host_state['primary-mac']))
    host_node.set_state(host_state)
    host_node.set_config(json.loads((import_path / 'node-config.json').read_text()))
    host_node.authn_key = json.loads((import_path / 'authn-key.json').read_text())

  async with asyncio.TaskGroup() as task_group:
    tftpd_ready = asyncio.Event()
    task_group.create_task(tftpd(ctx, tftpd_ready))
    dhcp_proxy_ready = asyncio.Event()
    task_group.create_task(dhcp_proxy(ctx, dhcp_proxy_ready))
    api_ready = asyncio.Event()
    task_group.create_task(api(ctx, api_ready))
    task_group.create_task(watch_nodes(ctx))
    await tftpd_ready.wait()
    await dhcp_proxy_ready.wait()
    await api_ready.wait()

async def prompt_host_ip():
  choices = []
  for adapter in filter(lambda a: a.nice_name != 'lo', ifaddr.get_adapters()):
    for ip in filter(lambda ip: ip.is_IPv4, adapter.ips):
      choices.append(questionary.Choice(f'{adapter.nice_name}: {ip.ip}', ip.ip))
  if len(choices) == 1:
    ip = choices[0].value
  elif len(choices) == 0:
    raise ErrorMessage('Unable to enumerate NICs and --listen is not specified')
  else:
    log.warning('There is more than one address to bind to and --listen is not specified')
    ip = await questionary.select("Multiple networks found, please select:", choices).ask_async()
    if ip is None:
      raise ErrorMessage('You must select an IP for the boot-server to listen on')
  return ipaddress.ip_address(ip)

def setup_logging():
  log.setLevel(getattr(logging, os.getenv('LOGLEVEL', 'INFO').upper(), 'INFO'))
  handler = logging.StreamHandler(sys.stderr)
  if os.getenv('LOGFORMAT', 'cli').lower() == 'logfmt':
    handler.setFormatter(logfmter.Logfmter(keys=['ts', 'at', 'component', 'msg'], # type: ignore
                                           mapping={'at': 'level', 'ts': 'asctime', 'component': 'name'},
                                           datefmt='%Y-%m-%dT%H:%M:%S%z'))
  log.addHandler(handler)


if __name__ == "__main__":
  try:
    asyncio.run(main())
  except KeyboardInterrupt as e:
    pass
  except ErrorMessage as e:
    sys.stderr.write(f'{e}\n')
