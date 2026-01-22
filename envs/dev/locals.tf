locals {
  identifier = "${var.identifier}-${var.env}"
  # rds_cluster_name = "${var.identifier}-${var.env}-rds-cluster"
  # vpc_id           = module.vpc.vpc_id
}


locals {
  vpc_name = "${var.identifier}-${var.env}-vpc"
  default_tags = {
  }
}