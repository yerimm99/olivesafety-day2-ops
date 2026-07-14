module "bastion" {
  source = "../../modules/bastion"

  project_name = var.project_name
  environment  = var.environment

  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.public_subnet_ids[0]

  allowed_ssh_cidr = var.bastion_allowed_ssh_cidr
  public_key_path  = var.bastion_public_key_path

  instance_type = "t3.micro"
}

output "bastion_instance_id" {
  value = module.bastion.instance_id
}

output "bastion_public_ip" {
  value = module.bastion.public_ip
}

output "bastion_public_dns" {
  value = module.bastion.public_dns
}

output "bastion_security_group_id" {
  value = module.bastion.security_group_id
}

output "bastion_iam_role_name" {
  value = module.bastion.iam_role_name
}
