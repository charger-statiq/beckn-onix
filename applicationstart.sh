#!/bin/bash

microk8s kubectl rollout restart deployment/onix -n statiq-dev
