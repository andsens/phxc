#!/usr/bin/env bash

wget -qO~/.local/bin/kpt https://github.com/kptdev/kpt/releases/download/v1.0.0-beta.49/kpt_linux_amd64
wget -qO~/.local/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/v1.28.4/bin/linux/amd64/kubectl
wget -qO~/.local/bin/k9s https://github.com/derailed/k9s/releases/download/v0.31.9/k9s_linux_amd64.deb
wget -qO- https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.3.0/kustomize_v5.3.0_linux_amd64.tar.gz | tar xzC ~/.local/bin/ kustomize
wget -qO- https://github.com/ahmetb/kubectx/releases/download/v0.9.5/kubectx_v0.9.5_linux_x86_64.tar.gz | tar xzC ~/.local/bin/ kubectx
wget -qO- https://github.com/ahmetb/kubectx/releases/download/v0.9.5/kubens_v0.9.5_linux_x86_64.tar.gz | tar xzC ~/.local/bin/ kubens
wget -qO- https://github.com/stern/stern/releases/download/v1.28.0/stern_1.28.0_linux_amd64.tar.gz | tar xzC ~/.local/bin stern
wget -qO- https://get.helm.sh/helm-v3.14.3-linux-amd64.tar.gz | tar xzC ~/.local/bin --strip-components 1 linux-amd64/helm
wget -qO- https://dl.smallstep.com/gh-release/cli/gh-release-header/v0.26.0/step_linux_0.26.0_amd64.tar.gz | tar xzC ~/.local/bin --strip-components 2 step_0.26.0/bin/step

chmod +x ~/.local/bin/{kubectl,kpt,k9s,kustomize,kubectx,kubens,stern,helm,step}
