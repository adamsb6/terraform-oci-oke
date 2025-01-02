# Copyright (c) 2022, 2023 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  tfscaled_workers_for_each = { for key, value in local.enabled_instance_pools: key => value if tobool(lookup(value, "ignore_initial_pool_size", false)) == false }
}

data "oci_core_subnet" "worker_subnet" {
  for_each = local.tfscaled_workers_for_each
  subnet_id = each.value.subnet_id
}

# Dynamic resource block for Instance Pool groups defined in worker_pools
resource "oci_core_instance_pool" "tfscaled_workers" {
  # Create an OCI Instance Pool resource for each enabled entry of the worker_pools map with that mode.
  for_each                  = local.tfscaled_workers_for_each
  compartment_id            = each.value.compartment_id
  display_name              = each.key
  size                      = each.value.size
  instance_configuration_id = oci_core_instance_configuration.workers[each.key].id
  defined_tags              = each.value.defined_tags
  freeform_tags             = each.value.freeform_tags

  dynamic "placement_configurations" {
    for_each = each.value.availability_domains
    iterator = ad

    content {
      availability_domain = ad.value

      # Value(s) specified on pool, or null to select automatically
      fault_domains = try(each.value.placement_fds, null)

      primary_vnic_subnets {
        subnet_id = each.value.subnet_id
        is_assign_ipv6ip = var.enable_ipv6
        ipv6address_ipv6subnet_cidr_pair_details {
          ipv6subnet_cidr = one(data.oci_core_subnet.worker_subnet[each.key].ipv6cidr_blocks)
        }
      }

      dynamic "secondary_vnic_subnets" {
        for_each = lookup(each.value, "secondary_vnics", {})
        iterator = vnic
        content {
          display_name = vnic.key
          subnet_id    = lookup(vnic.value, "subnet_id", each.value.subnet_id)
          is_assign_ipv6ip = var.enable_ipv6
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      display_name, defined_tags, freeform_tags,
      #placement_configurations,
    ]

    precondition {
      condition     = coalesce(each.value.image_id, "none") != "none"
      error_message = <<-EOT
      Missing image_id; check provided value if image_type is 'custom', or image_os/image_os_version if image_type is 'oke' or 'platform'.
        pool: ${each.key}
        image_type: ${coalesce(each.value.image_type, "none")}
        image_id: ${coalesce(each.value.image_id, "none")}
      EOT
    }

    # precondition {
    #   condition     = var.cni_type == "flannel"
    #   error_message = "Instance Pools require a cluster with `cni_type = flannel`."
    # }

    precondition {
      condition     = each.value.autoscale == false
      error_message = "Instance Pools do not support cluster autoscaler management."
    }
  }
}

resource "oci_core_instance_pool" "autoscaled_workers" {
  # Create an OCI Instance Pool resource for each enabled entry of the worker_pools map with that mode.
  for_each                  = { for key, value in local.enabled_instance_pools: key => value if tobool(lookup(value, "ignore_initial_pool_size", false)) == true }
  compartment_id            = each.value.compartment_id
  display_name              = each.key
  size                      = each.value.size
  instance_configuration_id = oci_core_instance_configuration.workers[each.key].id
  defined_tags              = each.value.defined_tags
  freeform_tags             = each.value.freeform_tags

  dynamic "placement_configurations" {
    for_each = each.value.availability_domains
    iterator = ad

    content {
      availability_domain = ad.value
      primary_vnic_subnets {
        subnet_id = each.value.subnet_id
        is_assign_ipv6ip = true
      }

      # Value(s) specified on pool, or null to select automatically
      fault_domains = try(each.value.placement_fds, null)

      dynamic "secondary_vnic_subnets" {
        for_each = lookup(each.value, "secondary_vnics", {})
        iterator = vnic
        content {
          display_name = vnic.key
          subnet_id    = lookup(vnic.value, "subnet_id", each.value.subnet_id)
          is_assign_ipv6ip = var.enable_ipv6
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      display_name, defined_tags, freeform_tags,
      placement_configurations, size
    ]

    precondition {
      condition     = coalesce(each.value.image_id, "none") != "none"
      error_message = <<-EOT
      Missing image_id; check provided value if image_type is 'custom', or image_os/image_os_version if image_type is 'oke' or 'platform'.
        pool: ${each.key}
        image_type: ${coalesce(each.value.image_type, "none")}
        image_id: ${coalesce(each.value.image_id, "none")}
      EOT
    }

    # precondition {
    #   condition     = var.cni_type == "flannel"
    #   error_message = "Instance Pools require a cluster with `cni_type = flannel`."
    # }

    precondition {
      condition     = each.value.autoscale == false
      error_message = "Instance Pools do not support cluster autoscaler management."
    }
  }
}
