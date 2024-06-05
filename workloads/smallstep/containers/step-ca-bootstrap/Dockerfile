FROM cr.step.sm/smallstep/step-ca-bootstrap@sha256:5270356cf91596afe18478eab60c6c0866b2cc62618f282d42827e58f84d6eae

RUN apk add bash
SHELL ["/bin/bash", "-Eeo", "pipefail", "-c"]
RUN /workspace/common-context/setup-alpine.sh
