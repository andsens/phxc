from typing import Any, cast
import uuid
from kubernetes_asyncio import client
from . import Context
from .node import Node
from .boot_events import kubernetes_node_ready
from kubernetes_asyncio import client, watch


async def watch_nodes(ctx: Context):
  async with client.ApiClient() as api:
    v1 = client.CoreV1Api(api)
    async with watch.Watch().stream(v1.list_node) as stream:
      async for event in stream:
        node = cast(Any, event)['object']
        if any(c.status == 'True' for c in node.status.conditions if c.type == 'Ready'):
          node = Node.get_by_machine_id(ctx, uuid.UUID(node.status.nodeInfo.machineId))
          if node is not None:
            image = node.booting_image
            if image is not None:
              del node.booting_image
              node.stable_image = image
              image.boot_results.log_success(node)
            kubernetes_node_ready(ctx, node)
