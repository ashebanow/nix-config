Followed manual steps to install k3s then rancher:

```
# install k3s cluster locally on yuzu
# curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=<VERSION> sh -s - server --cluster-init
# for our nix system, we include rancher-k3s.nix in our configuration.nix instead

# Save the kubeconfig to your workstation
#scp root@<IP_OF_LINUX_MACHINE>:/etc/rancher/k3s/k3s.yaml ~/.kube/config
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown -R ashebanow ~/.kube

# Edit the Rancher server URL in the kubeconfig to read 'yuzu' not localhost

# Install Rancher with Helm
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest

kubectl create namespace cattle-system

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/1.13.3/cert-manager.crds.yaml

helm repo add jetstack https://charts.jetstack.io

helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace

helm install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname=<IP_OF_LINUX_NODE>.sslip.io \
  --set replicas=1 \
  --set bootstrapPassword=<PASSWORD_FOR_RANCHER_ADMIN>
```

======================================================

```
sudo k3s kubectl cluster-info # EDITED SERVER NAME/IP
Kubernetes control plane is running at https://yuzu:6443
CoreDNS is running at https://yuzu:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
Metrics-server is running at https://yuzu:6443/api/v1/namespaces/kube-system/services/https:metrics-server:https/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

======================================================

NAME: cert-manager
LAST DEPLOYED: Wed Jan 17 13:14:04 2024
NAMESPACE: cert-manager
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
cert-manager v1.13.3 has been deployed successfully!

In order to begin issuing certificates, you will need to set up a ClusterIssuer
or Issuer resource (for example, by creating a 'letsencrypt-staging' issuer).

More information on the different types of issuers and how to configure them
can be found in our documentation:

https://cert-manager.io/docs/configuration/

For information on how to configure cert-manager to automatically provision
Certificates for Ingress resources, take a look at the `ingress-shim`
documentation:

https://cert-manager.io/docs/usage/ingress/

======================================================

helm install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname=yuzu.lan \
  --set replicas=1 \
  --set bootstrapPassword=zcXPFDDEZRhoQeGS

Note that the bootstrap password won't live long.

NAME: rancher
LAST DEPLOYED: Wed Jan 17 13:19:08 2024
NAMESPACE: cattle-system
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
Rancher Server has been installed.

NOTE: Rancher may take several minutes to fully initialize. Please standby while Certificates are being issued, Containers are started and the Ingress rule comes up.

Check out our docs at https://rancher.com/docs/

If you provided your own bootstrap password during installation, browse to https://yuzu.lan to get started.

If this is the first time you installed Rancher, get started by running this command and clicking the URL it generates:

```
echo https://yuzu/dashboard/?setup=$(kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}')
```

To get just the bootstrap password on its own, run:

```
kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}{{ "\n" }}'
```

Root account is 'admin'.