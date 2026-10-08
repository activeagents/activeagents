# Plans the module against a mock provider, so it runs without GCP
# credentials: terraform init -backend=false && terraform test

mock_provider "google" {}

variables {
  project_id  = "example-project"
  environment = "staging"
  network_id  = "projects/example-project/global/networks/sandbox-network"
  subnet_id   = "projects/example-project/regions/us-central1/subnetworks/sandbox-subnet"
}

run "host_account_keeps_only_log_and_metric_roles" {
  command = plan

  assert {
    condition     = toset(keys(google_project_iam_member.host_project_roles)) == toset(["roles/logging.logWriter", "roles/monitoring.metricWriter"])
    error_message = "The host's only project-level roles must be log and metric writer."
  }
}

run "host_account_publishes_its_credentials_and_reads_nothing" {
  command = plan

  assert {
    condition = alltrue([
      google_secret_manager_secret.client_credentials["cert"].secret_id == "incus-client-cert-staging",
      google_secret_manager_secret.client_credentials["key"].secret_id == "incus-client-key-staging",
    ])
    error_message = "The client credential secrets must keep the names the host and the app use."
  }

  assert {
    condition = alltrue([
      for binding in google_secret_manager_secret_iam_member.host_publishes_client_credentials :
      binding.role == "roles/secretmanager.secretVersionAdder"
    ]) && length(google_secret_manager_secret_iam_member.host_publishes_client_credentials) == 2
    error_message = "The host may only add versions to its two credential secrets."
  }

  assert {
    condition     = length(google_secret_manager_secret_iam_member.app_reads_client_credentials) == 0
    error_message = "Without an app service account nobody gets read access."
  }
}

run "host_account_publishes_its_server_certificate_and_reads_nothing" {
  command = plan

  assert {
    condition     = google_secret_manager_secret.server_cert.secret_id == "incus-server-cert-staging" && output.server_cert_secret == "incus-server-cert-staging"
    error_message = "The server certificate secret must be named incus-server-cert-<env>, as the app expects."
  }

  assert {
    condition = alltrue([
      google_secret_manager_secret_iam_member.host_publishes_server_cert.secret_id == "incus-server-cert-staging",
      google_secret_manager_secret_iam_member.host_publishes_server_cert.role == "roles/secretmanager.secretVersionAdder",
    ])
    error_message = "The host may only add versions to the server certificate secret."
  }

  assert {
    condition     = length(google_secret_manager_secret_iam_member.app_reads_server_cert) == 0
    error_message = "Without an app service account nobody reads the server certificate."
  }
}

run "app_account_reads_the_server_certificate" {
  command = plan

  variables {
    app_service_account = "activeagents-staging@example-project.iam.gserviceaccount.com"
  }

  assert {
    condition = alltrue([
      google_secret_manager_secret_iam_member.app_reads_server_cert[0].secret_id == "incus-server-cert-staging",
      google_secret_manager_secret_iam_member.app_reads_server_cert[0].role == "roles/secretmanager.secretAccessor",
      google_secret_manager_secret_iam_member.app_reads_server_cert[0].member == "serviceAccount:activeagents-staging@example-project.iam.gserviceaccount.com",
    ])
    error_message = "The app must read the server certificate it verifies the daemon with."
  }
}

run "startup_script_names_the_internal_ip_and_publishes_the_server_certificate" {
  command = plan

  assert {
    condition = alltrue([
      strcontains(google_compute_instance.incus_host.metadata_startup_script, "/usr/local/sbin/setup-incus-host server-cert \"$INTERNAL_IP\""),
      strcontains(google_compute_instance.incus_host.metadata_startup_script, "publish_secret incus-server-cert-staging /var/lib/incus/server.crt"),
    ])
    error_message = "The startup script must make the server certificate name the internal IP, then publish it."
  }
}

run "app_account_reads_the_credentials" {
  command = plan

  variables {
    app_service_account = "activeagents-staging@example-project.iam.gserviceaccount.com"
  }

  assert {
    condition = alltrue([
      for kind in ["cert", "key"] :
      google_secret_manager_secret_iam_member.app_reads_client_credentials[kind].role == "roles/secretmanager.secretAccessor" &&
      google_secret_manager_secret_iam_member.app_reads_client_credentials[kind].member == "serviceAccount:activeagents-staging@example-project.iam.gserviceaccount.com"
    ])
    error_message = "The app must read both credential secrets, and only those."
  }
}

run "startup_script_restricts_egress_and_only_adds_versions" {
  command = plan

  assert {
    condition     = strcontains(google_compute_instance.incus_host.metadata_startup_script, "SANDBOX_EGRESS_REJECT='169.254.0.0/16,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16' /usr/local/sbin/setup-incus-host egress-acl")
    error_message = "The startup script must apply the egress ACL with the module's ranges."
  }

  assert {
    condition     = strcontains(google_compute_instance.incus_host.metadata_startup_script, base64encode(file("../../../scripts/setup-incus-host.sh")))
    error_message = "The startup script must install the current scripts/setup-incus-host.sh."
  }

  assert {
    condition     = !strcontains(google_compute_instance.incus_host.metadata_startup_script, "gcloud secrets create")
    error_message = "The host must not create secrets; Terraform does."
  }

  assert {
    condition     = strcontains(output.egress_acl_command, "bash -s egress-acl\" < scripts/setup-incus-host.sh")
    error_message = "The output must give a command that applies the ACL to a running host."
  }
}

run "serves_no_app_by_default" {
  command = plan

  assert {
    condition = alltrue([
      length(google_compute_route.bridge) == 0,
      length(google_compute_firewall.bridge_app) == 0,
      !coalesce(google_compute_instance.incus_host.can_ip_forward, false),
    ])
    error_message = "Without app_source_ranges the host must not forward, and nothing may route to the bridge or reach port 8080."
  }

  assert {
    condition     = google_compute_firewall.incus_api.source_ranges == toset(["10.0.0.0/8"])
    error_message = "Without app_source_ranges the Incus API must keep its rule as before."
  }
}

run "serves_the_platform_app" {
  command = plan

  variables {
    app_source_ranges = ["10.8.0.0/28"]
  }

  assert {
    condition     = google_compute_instance.incus_host.can_ip_forward == true
    error_message = "The host must forward packets for the bridge."
  }

  assert {
    condition = alltrue([
      google_compute_route.bridge[0].dest_range == "10.100.0.0/24",
      google_compute_route.bridge[0].network == "projects/example-project/global/networks/sandbox-network",
      output.bridge_cidr == "10.100.0.0/24",
    ])
    error_message = "The VPC must route the bridge's subnet to the host."
  }

  assert {
    condition     = strcontains(google_compute_instance.incus_host.metadata_startup_script, "ipv4.address: ${cidrhost(output.bridge_cidr, 1)}/${split("/", output.bridge_cidr)[1]}")
    error_message = "The routed subnet must be the one the preseed gives incusbr0."
  }

  assert {
    condition     = google_compute_firewall.incus_api.source_ranges == toset(["10.8.0.0/28"])
    error_message = "Only the app's range may reach the Incus API."
  }

  assert {
    condition = alltrue([
      google_compute_firewall.bridge_app[0].source_ranges == toset(["10.8.0.0/28"]),
      google_compute_firewall.bridge_app[0].destination_ranges == toset(["10.100.0.0/24"]),
      google_compute_firewall.bridge_app[0].target_tags == toset(["incus-host"]),
      [for rule in google_compute_firewall.bridge_app[0].allow : "${rule.protocol}:${join(",", rule.ports)}"] == ["tcp:8080"],
    ])
    error_message = "Only the app's range may reach the containers on the bridge, and only on 8080."
  }
}

run "refuses_app_ranges_with_host_bits" {
  command = plan

  variables {
    app_source_ranges = ["10.8.0.1/28"]
  }

  expect_failures = [var.app_source_ranges]
}

run "refuses_project_level_secret_accessor" {
  command = plan

  variables {
    host_project_roles = ["roles/logging.logWriter", "roles/secretmanager.secretAccessor"]
  }

  expect_failures = [google_project_iam_member.host_project_roles]
}

run "refuses_project_level_secret_version_adder" {
  command = plan

  variables {
    host_project_roles = ["roles/logging.logWriter", "roles/secretmanager.secretVersionAdder"]
  }

  expect_failures = [google_project_iam_member.host_project_roles]
}

run "refuses_project_level_object_viewer" {
  command = plan

  variables {
    host_project_roles = ["roles/logging.logWriter", "roles/storage.objectViewer"]
  }

  expect_failures = [google_project_iam_member.host_project_roles]
}

run "refuses_project_level_token_creator" {
  command = plan

  variables {
    host_project_roles = ["roles/logging.logWriter", "roles/iam.serviceAccountTokenCreator"]
  }

  expect_failures = [google_project_iam_member.host_project_roles]
}

run "refuses_project_level_service_account_user" {
  command = plan

  variables {
    host_project_roles = ["roles/logging.logWriter", "roles/iam.serviceAccountUser"]
  }

  expect_failures = [google_project_iam_member.host_project_roles]
}

run "refuses_project_level_project_iam_admin" {
  command = plan

  variables {
    host_project_roles = ["roles/logging.logWriter", "roles/resourcemanager.projectIamAdmin"]
  }

  expect_failures = [google_project_iam_member.host_project_roles]
}

run "refuses_project_level_security_admin" {
  command = plan

  variables {
    host_project_roles = ["roles/logging.logWriter", "roles/iam.securityAdmin"]
  }

  expect_failures = [google_project_iam_member.host_project_roles]
}

run "refuses_project_level_editor" {
  command = plan

  variables {
    host_project_roles = ["roles/logging.logWriter", "roles/editor"]
  }

  expect_failures = [google_project_iam_member.host_project_roles]
}

run "refuses_project_level_viewer" {
  command = plan

  variables {
    host_project_roles = ["roles/logging.logWriter", "roles/viewer"]
  }

  expect_failures = [google_project_iam_member.host_project_roles]
}

run "refuses_project_level_workload_identity_user" {
  command = plan

  variables {
    host_project_roles = ["roles/logging.logWriter", "roles/iam.workloadIdentityUser"]
  }

  expect_failures = [google_project_iam_member.host_project_roles]
}

run "refuses_project_level_role_admin" {
  command = plan

  variables {
    host_project_roles = ["roles/logging.logWriter", "roles/iam.roleAdmin"]
  }

  expect_failures = [google_project_iam_member.host_project_roles]
}

run "refuses_project_level_compute_instance_admin" {
  command = plan

  variables {
    host_project_roles = ["roles/logging.logWriter", "roles/compute.instanceAdmin.v1"]
  }

  expect_failures = [google_project_iam_member.host_project_roles]
}

run "refuses_project_level_cloud_build_editor" {
  command = plan

  variables {
    host_project_roles = ["roles/logging.logWriter", "roles/cloudbuild.builds.editor"]
  }

  expect_failures = [google_project_iam_member.host_project_roles]
}

run "refuses_project_level_custom_role" {
  command = plan

  variables {
    host_project_roles = ["roles/logging.logWriter", "projects/example-project/roles/sandboxHost"]
  }

  expect_failures = [google_project_iam_member.host_project_roles]
}

run "allows_the_trace_writer_role" {
  command = plan

  variables {
    host_project_roles = ["roles/logging.logWriter", "roles/monitoring.metricWriter", "roles/cloudtrace.agent"]
  }

  assert {
    condition     = length(google_project_iam_member.host_project_roles) == 3
    error_message = "Every permitted telemetry role must be grantable."
  }
}

run "refuses_ipv6_egress_ranges" {
  command = plan

  variables {
    sandbox_egress_reject_ranges = ["169.254.0.0/16", "fd00::/8"]
  }

  expect_failures = [var.sandbox_egress_reject_ranges]
}

run "refuses_ranges_with_host_bits" {
  command = plan

  variables {
    sandbox_egress_reject_ranges = ["10.1.2.3/8"]
  }

  expect_failures = [var.sandbox_egress_reject_ranges]
}

# Last, because it applies (against the mock provider): the command names the
# host's internal IP, which a plan does not know yet.
run "server_cert_command_fixes_and_publishes_a_running_host" {
  command = apply

  override_resource {
    target = google_compute_instance.incus_host
    values = {
      network_interface = { network_ip = "10.10.0.2" }
    }
  }

  assert {
    condition = (
      strcontains(output.server_cert_command, "INCUS_SERVER_CERT_SECRET=incus-server-cert-staging INCUS_SECRET_PROJECT=example-project bash -s server-cert 10.10.0.2\"") &&
      endswith(output.server_cert_command, "< scripts/setup-incus-host.sh")
    )
    error_message = "The output must give a command that makes a running host's server certificate name its internal IP and publishes it."
  }
}
