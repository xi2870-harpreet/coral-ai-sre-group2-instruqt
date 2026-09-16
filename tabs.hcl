# Terminal — command-line access to the k8s VM.
resource "terminal" "shell" {
  target = resource.vm.k8s
  shell  = "/bin/bash"
}

# The Reef Shop storefront (frontend service, NodePort 30080).
resource "service" "shop" {
  target = resource.vm.k8s
  port   = 30080
  scheme = "http"
}

# Prometheus UI (NodePort 30990).
resource "service" "prometheus" {
  target = resource.vm.k8s
  port   = 30990
  scheme = "http"
}

# Coral local UI, forwarded to 11457.
resource "service" "coral_ui" {
  target = resource.vm.k8s
  port   = 11457
  scheme = "http"
}

# FINDING (confirmed): `editor` workspace target only accepts `container`,
# not `vm` (instruqt lab validate: 'target type "vm" is not allowed').
# The original track used code-type tabs pointed at directories on the VM
# (Data Files: /root/data, Spec Editor: /root/specs) - there's no 2.0
# equivalent for VM-hosted files, so this is ported as a deviation: the
# instructions use the Terminal (cat / nano) instead of a dedicated tab.

# Cloud Credentials tab - behind the feature_cloud_providers flag per the
# group brief. The only track in the round that can test this.
resource "cloud_credentials" "aws" {
  aws_account {
    target = resource.aws_account.bedrock
    users  = ["student"]
  }
}
