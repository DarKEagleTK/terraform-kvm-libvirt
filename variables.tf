variable "memoryMB" { 
    default = 1024*4
}
variable "cpu" { 
    default = 4
}

variable gateway {
  default = "10.99.0.1"
}

variable nameserver {
  default = "192.168.0.254"
}

variable network_name {
  default = "Interne"
}

variable workers_count {
    default = 1
}