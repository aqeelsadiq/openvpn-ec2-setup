variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket"
}

variable "acl" {
  type        = string
  description = "ACL for the bucket"
  default     = "private"
}

variable "env" {
  type        = string
  description = "Environment, e.g., dev, prod"
}

variable "tags" {
  type        = map(string)
  description = "Additional tags for the bucket"
  default     = {}
}

variable "versioning_enabled" {
  type        = bool
  default     = true
}

variable "sse_enabled" {
  type        = bool
  default     = true
}
