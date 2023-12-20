variable "app_db_pw_index" {
  type        = number
  description = "increment this value when the database password should be changed"
  default     = 0
}

variable "domain" {
  type    = string
  default = "3tier.clarkwinters.com"
}

variable "app_name" {
  type    = string
  default = "3tier"
}

variable "vpc_cidr_block" {
  type    = string
  default = "10.0.0.0/16"
}

variable "web_subnets" {
  type = set(object({
    cidr_block = string
    az         = string
  }))
  default = [{
    cidr_block = "10.0.0.0/26"
    az         = "us-east-2a"
    }, {
    cidr_block = "10.0.0.64/26"
    az         = "us-east-2b"
    }, {
    cidr_block = "10.0.0.128/26"
    az         = "us-east-2c"
  }]
}

variable "api_subnets" {
  type = set(object({
    cidr_block = string
    az         = string
  }))
  default = [{
    cidr_block = "10.0.1.0/26"
    az         = "us-east-2a"
    }, {
    cidr_block = "10.0.1.64/26"
    az         = "us-east-2b"
    }, {
    cidr_block = "10.0.1.128/26"
    az         = "us-east-2c"
  }]
}

variable "db_subnets" {
  type = set(object({
    cidr_block = string
    az         = string
  }))
  default = [{
    cidr_block = "10.0.2.0/26"
    az         = "us-east-2a"
    }, {
    cidr_block = "10.0.2.64/26"
    az         = "us-east-2b"
    }, {
    cidr_block = "10.0.2.128/26"
    az         = "us-east-2c"
  }]
}

variable "public_subnets" {
  type = set(object({
    cidr_block = string
    az         = string
  }))
  default = [{
    cidr_block = "10.0.3.0/26"
    az         = "us-east-2a"
    }, {
    cidr_block = "10.0.3.64/26"
    az         = "us-east-2b"
    }, {
    cidr_block = "10.0.3.128/26"
    az         = "us-east-2c"
  }]
}

variable "web_tags" {
  type = object({
    Name      = string
    component = string
  })
  default = {
    Name      = "3tier-web"
    component = "web"
  }
}

variable "api_tags" {
  type = object({
    Name      = string
    component = string
  })
  default = {
    Name      = "3tier-api"
    component = "api"
  }
}

variable "db_tags" {
  type = object({
    Name      = string
    component = string
  })
  default = {
    Name      = "pg-3tier-db"
    component = "db"
  }
}

variable "public_tags" {
  type = object({
    Name = string
  })
  default = {
    Name = "3tier-public"
  }
}

variable "web_port" {
  type    = number
  default = 3000
}

variable "api_port" {
  type    = number
  default = 8080
}

variable "db_port" {
  type    = number
  default = 5432
}

variable "public_port" {
  type    = number
  default = 443
}

variable "db_name" {
  description = "name of the database on the RDS cluster"
  type        = string
  default     = "pg3tier"
}

variable "api_service_name" {
  type    = string
  default = "api"
}
