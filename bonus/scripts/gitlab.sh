#!/bin/bash
set -euo pipefail

exec kubectl --context k3d-iot -n gitlab port-forward svc/gitlab 8081:8081
