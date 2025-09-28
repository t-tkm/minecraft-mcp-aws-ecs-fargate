output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.minecraft_proxy.id
}

output "public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_eip.minecraft_proxy.public_ip
}

output "elastic_ip" {
  description = "Elastic IP address of the EC2 instance"
  value       = aws_eip.minecraft_proxy.public_ip
}
