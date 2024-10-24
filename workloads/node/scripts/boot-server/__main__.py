'''boot-server
Usage:
  boot-server [options]

Options:
  --listen IP          The IP to bind to [default: <prompt>]
  -r --root PATH       The root directory for the boot-server
                       [default: /data]
  --images PATH        Path to the OS images the boot-server serves
                       [default: <root>/images]
  --steppath PATH      Path to the smallstep root where the root & secureboot
                       keys & certificates are located
                       (smallstep secrets transfer disabled if not specified)
  --admin-pubkey PATH  Path to the admin public key, used for uploading images
                       [default: <root>/admin.pub]
  --certfile PATH      Path to the TLS certificate bundle for the
                       boot-server API [default: <root>/tls/tls.crt]
  --keyfile PATH       Path to the TLS key for the boot-server API
                       [default: <root>/tls/tls.key]
  --boot-map PATH      Path to map of "vendor-client/arch" DHCP options to TFTP
                       boot file paths [default: <root>/boot-map.yaml]
  --user USER          Drop privileges after setup and run as specified user
  --import PATH        Import the state, config, and authn-key of the host node
                       from the specified path
  --etcd URL           etcd URL for storing node states, configs, and authn-keys
                       An ephemeral in-memory KV store will be used if not
                       specified and boot-server will prompt on the terminal
                       when a node needs to be configured.
'''

import asyncio, ipaddress, logging, os, pwd, signal, sys
import urllib.parse
from pathlib import Path
import docopt
from . import __name__ as root_name, ErrorMessage
from .context import Context
from .dhcp_proxy import dhcp_proxy
from .registry import Registry
from .inmemorykvstore import InMemoryKVStore
from .api import api
from .tftpd import tftpd
from .jwt_checker import JWTChecker
import etcd, ifaddr, logfmter, questionary

log = logging.getLogger(root_name)

async def main():
  params = docopt.docopt(__doc__)
  setup_logging()

  shutdown_event = asyncio.Event()
  loop = asyncio.get_running_loop()
  loop.add_signal_handler(signal.SIGINT, lambda: shutdown_event.set())
  loop.add_signal_handler(signal.SIGTERM, lambda: shutdown_event.set())

  host_ip = ipaddress.ip_address(params['--listen']) if params['--listen'] != '<prompt>' else await prompt_host_ip()
  root: Path = Path.cwd() if params['--root'] == '$PWD' else Path(params['--root'])
  images: Path = root / 'images' if params['--images'] == '<root>/images' else Path(params['--images'])
  certfile: Path = root / 'tls/tls.crt' if params['--certfile'] == '<root>/tls/tls.crt' else params['--certfile']
  keyfile: Path = root / 'tls/tls.key' if params['--keyfile'] == '<root>/tls/tls.key' else params['--keyfile']
  admin_pubkey: Path = root if params['--admin-pubkey'] == '<root>/admin.pub' else Path(params['--admin-pubkey'])
  steppath: Path | None = Path(params['--steppath']) if params['--steppath'] is not None else None
  boot_map: Path = root / 'boot-map.yaml' if params['--boot-map'] == '<root>/boot-map.yaml' else root / Path(params['--boot-map'])


  if params['--etcd'] is not None:
    etcd_parts = urllib.parse.urlparse(params['--etcd'])
    kv_client = etcd.Client(protocol=etcd_parts.scheme, host=etcd_parts.hostname, port=etcd_parts.port, allow_reconnect=True)
  else:
    kv_client = InMemoryKVStore()

  jwt_checker = JWTChecker(kv_client, admin_pubkey)

  registry = Registry(kv_client, admin_pubkey)
  if params['--import'] is not None:
    registry.import_host_info(Path(params['--import']))

  context: Context = {
    'registry': registry,
    'jwt_checker': jwt_checker,
    'kv_client': kv_client,
  }

  async with asyncio.TaskGroup() as task_group:
    tftpd_ready = asyncio.Event()
    task_group.create_task(tftpd(tftpd_ready, context, host_ip, images))
    dhcp_proxy_ready = asyncio.Event()
    task_group.create_task(dhcp_proxy(dhcp_proxy_ready, context, boot_map, host_ip))
    api_ready = asyncio.Event()
    task_group.create_task(api(api_ready, context,
                               host_ip, images, certfile, keyfile, steppath))
    await tftpd_ready.wait()
    await dhcp_proxy_ready.wait()
    await api_ready.wait()
    if params['--user'] is not None:
      user_uid = pwd.getpwnam(params['--user']).pw_uid
      log.info(f'Sockets bound, dropping to user {params['--user']} (UID: {user_uid})')
      os.setuid(user_uid)

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
    handler.setFormatter(logfmter.Logfmter(keys=['ts', 'at', 'component', 'msg'],
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
