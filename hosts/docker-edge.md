Portainer Edge Agent:
---------------------
* need NFS mounts for data on servers
* need to handle secrets for EDGE_ID and EDGE_KEY
* should we make the container name vary by HOSTNAME?

```bash
docker run -d \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /var/lib/docker/volumes:/var/lib/docker/volumes \
  -v /:/host \
  -v portainer_agent_data:/data \
  --restart always \
  -e EDGE=1 \
  -e EDGE_ID=REPLACE_ME \
  -e EDGE_KEY=REPLACE_ME \
  -e EDGE_INSECURE_POLL=1 \
  --name portainer_edge_agent \
  portainer/agent:2.19.1
```
