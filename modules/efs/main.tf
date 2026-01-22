resource "aws_efs_file_system" "this" {
  creation_token = "${var.env}-openvpn-efs"
  encrypted      = true

  tags = {
    Name = "${var.env}-openvpn-efs"
  }
}

resource "aws_efs_mount_target" "this" {
  for_each = toset(var.private_subnet_ids)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value
  security_groups = [var.efs_sg_id]
}
