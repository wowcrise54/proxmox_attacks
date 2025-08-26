# SDN Module Variables

variable "zone_name" {
  description = "Name of the SDN zone"
  type        = string
}

variable "management_vnet" {
  description = "Management VNET name"
  type        = string
}

variable "infrastructure_vnet" {
  description = "Infrastructure VNET name"
  type        = string
}

variable "services_vnet" {
  description = "Services VNET name"
  type        = string
}

variable "management_subnet" {
  description = "Management subnet CIDR"
  type        = string
}

variable "infrastructure_subnet" {
  description = "Infrastructure subnet CIDR"
  type        = string
}

variable "services_subnet" {
  description = "Services subnet CIDR"
  type        = string
}

variable "dhcp_ranges" {
  description = "DHCP ranges for each network"
  type = map(object({
    start = string
    end   = string
  }))
}