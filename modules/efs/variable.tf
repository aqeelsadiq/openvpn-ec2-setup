variable "env" {}
variable "private_subnet_ids" {
  description = "Private subnet IDs for EFS mount targets"
  type        = list(string)
}
variable "efs_sg_id" {}
