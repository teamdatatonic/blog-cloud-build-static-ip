terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.51.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "4.51.0"
    }
  }
  backend "gcs" {
    bucket = "cloud-build-static-ip-tf-state"
    prefix = "terraform/state"
  }
}
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

// Step 1
resource "google_project_service" "enable_cloud_build" {
  project                    = var.project_id
  service                    = "cloudbuild.googleapis.com"
  disable_dependent_services = true
}
resource "google_project_service" "enable_service_networking" {
  project                    = var.project_id
  service                    = "servicenetworking.googleapis.com"
  disable_dependent_services = true
}

// Step 2
resource "google_compute_network" "vpc_network" {
  project                 = var.project_id
  name                    = var.vpc_network_name
  auto_create_subnetworks = false
  mtu                     = 1460
}

// Step 3
resource "google_compute_global_address" "named_private_ip" {
  provider      = google-beta
  name          = var.named_private_ip_name
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  network       = google_compute_network.vpc_network.name
  address       = var.named_private_ip
  prefix_length = var.named_private_ip_prefix_length
}

// Step 4
resource "google_service_networking_connection" "service_producer_connection" {
  network                 = "projects/${var.project_id}/global/networks/${google_compute_network.vpc_network.name}"
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.named_private_ip.name]
}

// Step 5
resource "google_cloudbuild_worker_pool" "private_worker_pool" {
  name     = var.private_worker_pool_name
  location = var.region
  project  = var.project_id
  worker_config {
    disk_size_gb   = 100
    machine_type   = "e2-medium"
    no_external_ip = true
  }
  network_config {
    peered_network = "projects/${var.project_id}/global/networks/${google_compute_network.vpc_network.name}"
  }
  depends_on = [google_service_networking_connection.service_producer_connection, google_project_service.enable_cloud_build]
}

// Step 6
resource "google_compute_subnetwork" "proxy_subnet" {
  name                     = "${google_compute_network.vpc_network.name}-proxy-subnet"
  ip_cidr_range            = var.vm_subnet_range
  network                  = google_compute_network.vpc_network.name
  region                   = var.region
  private_ip_google_access = false
  project                  = var.project_id
}

// Step 7
resource "google_compute_address" "static_ip" {
  name         = var.static_ip_name
  project      = var.project_id
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "STANDARD"
}

// Step 8
resource "google_compute_instance" "proxy_vm" {
  name         = "proxy-vm"
  project      = var.project_id
  zone         = var.zone
  machine_type = "n1-standard-1"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
  tags                    = ["proxy-srv"]
  metadata_startup_script = file("setup_proxy.sh")

  network_interface {
    subnetwork = google_compute_subnetwork.proxy_subnet.name
    network_ip = var.vm_ip_address
    access_config {
      nat_ip       = google_compute_address.static_ip.address
      network_tier = "STANDARD"
    }
  }
}

// Step 9
resource "google_compute_firewall" "proxy_ingress" {
  name    = "allow-proxy-ingress"
  network = google_compute_network.vpc_network.name

  # Source range is the range we used to peer into the service produces network. i.e. named_private_ip
  source_ranges = ["${var.named_private_ip}/${var.named_private_ip_prefix_length}"]
  allow {
    protocol = "tcp"
    ports    = ["9231"] # If you change this, make sure you're also changing it inside setup_proxy.sh
  }
  target_tags = ["proxy-srv"]
}