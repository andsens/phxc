FROM cr.step.sm/smallstep/step-ca-bootstrap@sha256:5270356cf91596afe18478eab60c6c0866b2cc62618f282d42827e58f84d6eae

RUN apk add jq gettext py3-virtualenv; \
  virtualenv /usr/local/lib/yq; \
  /usr/local/lib/yq/bin/pip3 install yq; \
  ln -s /usr/local/lib/yq/bin/yq /usr/local/bin/yq
