'''boot-server
Usage:
  boot-server [options]

Options:
  --bind-ip IP         The IP to bind to [default: 127.0.0.1]
  -r --root PATH       The root directory for the boot-server
                       [default: $PWD]
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
  --import             Import the state, config, and authn-key of the host node
  --etcd URL           etcd URL for storing node states, configs, and authn-keys
'''

import asyncio, logging, os, pwd, signal, sys
import urllib.parse
import logfmter
from pathlib import Path
import docopt
from . import __name__ as root_name
from .dhcp_proxy import dhcp_proxy
from .registry import NodeRegistry
from .api import api
from .tftpd import tftpd
from .tracker import BootTracker
import etcd

log = logging.getLogger(root_name)

async def main():
  params = docopt.docopt(__doc__)
  setup_logging()

  shutdown_event = asyncio.Event()
  loop = asyncio.get_running_loop()
  loop.add_signal_handler(signal.SIGINT, lambda: shutdown_event.set())
  loop.add_signal_handler(signal.SIGTERM, lambda: shutdown_event.set())

  bind_ip = params['--bind-ip']
  root: Path = Path.cwd() if params['--root'] == '$PWD' else Path(params['--root'])
  images: Path = root / 'images' if params['--images'] == '<root>/images' else Path(params['--images'])
  certfile: Path = root / 'tls/tls.crt' if params['--certfile'] == '<root>/tls/tls.crt' else params['--certfile']
  keyfile: Path = root / 'tls/tls.key' if params['--keyfile'] == '<root>/tls/tls.key' else params['--keyfile']
  admin_pubkey: Path = root if params['--admin-pubkey'] == '<root>/admin.pub' else Path(params['--admin-pubkey'])
  steppath: Path | None = Path(params['--steppath']) if params['--steppath'] is not None else None
  boot_map: Path = root / 'boot-map.yaml' if params['--boot-map'] == '<root>/boot-map.yaml' else root / Path(params['--boot-map'])


  if params['--etcd'] is not None:
    etcd_parts = urllib.parse.urlparse(params['--etcd'])
    kvClient = etcd.Client(protocol=etcd_parts.scheme, host=etcd_parts.hostname, port=etcd_parts.port)

  node_registry = NodeRegistry(kvClient, admin_pubkey)
  if params['--import']:
    node_registry.import_host_info(root)
  boot_tracker = BootTracker(node_registry)

  async with asyncio.TaskGroup() as task_group:
    tftpd_ready = asyncio.Event()
    task_group.create_task(tftpd(tftpd_ready, shutdown_event, boot_tracker, bind_ip, images))
    dhcp_proxy_ready = asyncio.Event()
    task_group.create_task(dhcp_proxy(dhcp_proxy_ready, shutdown_event, boot_tracker, boot_map, bind_ip))
    registry_ready = asyncio.Event()
    task_group.create_task(api(registry_ready, shutdown_event, boot_tracker, node_registry,
                               bind_ip, images, certfile, keyfile, steppath=steppath))
    await tftpd_ready.wait()
    await dhcp_proxy_ready.wait()
    await registry_ready.wait()
    if params['--user'] is not None:
      user_uid = pwd.getpwnam(params['--user']).pw_uid
      log.info(f'Sockets bound, dropping to user {params['--user']} (UID: {user_uid})')
      os.setuid(user_uid)

def setup_logging():
  log.setLevel(getattr(logging, os.getenv('LOGLEVEL', 'INFO').upper(), 'INFO'))
  handler = logging.StreamHandler(sys.stderr)
  handler.setFormatter(logfmter.Logfmter(keys=['ts', 'at', 'component', 'msg'],
                                         mapping={'at': 'level', 'ts': 'asctime', 'component': 'name'},
                                         datefmt='%Y-%m-%dT%H:%M:%S%z'))
  log.addHandler(handler)


if __name__ == "__main__":
  asyncio.run(main())
