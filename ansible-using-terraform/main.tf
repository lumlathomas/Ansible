# creating main.tf file using new keypair 

# Configure the AWS provider
provider "aws" {
  region = "eu-west-2" # Change this to your desired AWS region
}

# Generate a new SSH key pair
resource "tls_private_key" "ansible_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save the private key to a file
resource "local_file" "private_key" {
  filename        = "ansible_key.pem"
  content         = tls_private_key.ansible_key.private_key_pem
  file_permission = "0400" # Read-only for the owner
}

# Upload the public key to AWS
resource "aws_key_pair" "ansible_key" {
  key_name   = "ansible-key" # Name of the key pair in AWS
  public_key = tls_private_key.ansible_key.public_key_openssh
}

# Create a security group to allow SSH access from the Ansible control node
resource "aws_security_group" "ansible_sg" {
  name        = "ansible-sg"
  description = "Allow SSH from Ansible control node"

  # Allow SSH from the control node to target nodes
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # You may restrict this to the control node IP later
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create the Ansible control node
resource "aws_instance" "ansible_control_node" {
  ami           = "ami-0e56583ebfdfc098f" # Use the correct AMI for Amazon Linux
  instance_type = "t2.micro"
  key_name      = aws_key_pair.ansible_key.key_name
  vpc_security_group_ids = [aws_security_group.ansible_sg.id]

  tags = {
    Name = "Ansible-Control-Node"
  }

  provisioner "file" {
    source      = "ansible_key.pem"
    destination = "/home/ec2-user/.ssh/ansible_key.pem"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 400 /home/ec2-user/.ssh/ansible_key.pem", # Set correct permissions for the private key
      "sudo yum install -y ansible" # Install Ansible
    ]
  }

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.ansible_key.private_key_pem
    host        = self.public_ip
  }
}

# Create the target node(s)
resource "aws_instance" "target_node" {
  count         = 2 # Create 2 target nodes
  ami           = "ami-0e56583ebfdfc098f"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.ansible_key.key_name
  vpc_security_group_ids = [aws_security_group.ansible_sg.id]

  tags = {
    Name = "Target-Node-${count.index + 1}"
  }
}

# Output the public IPs of the instances
output "ansible_control_node_public_ip" {
  value = aws_instance.ansible_control_node.public_ip
}

output "target_nodes_public_ips" {
  value = aws_instance.target_node[*].public_ip
}

# Generate the Ansible inventory file dynamically
resource "local_file" "inventory" {
  filename = "inventory"
  content  = <<-EOT
    [target_hosts]
    %{ for ip in aws_instance.target_node[*].public_ip ~}
    ${ip} ansible_ssh_private_key_file=/home/ec2-user/.ssh/ansible_key.pem ansible_user=ec2-user
    %{ endfor ~}
  EOT
}

# Run the Ansible playbook from the control node
resource "null_resource" "run_ansible" {
  depends_on = [aws_instance.ansible_control_node, aws_instance.target_node, local_file.inventory]

  # SSH Connection Configuration
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.ansible_key.private_key_pem
    host        = aws_instance.ansible_control_node.public_ip
  }

  # Copy the inventory file to the control node
  provisioner "file" {
    source      = "inventory"
    destination = "/tmp/inventory"
  }

  # Copy the Ansible playbook to the control node
  provisioner "file" {
    source      = "loop_playbook.yml"
    destination = "/tmp/loop_playbook.yml"
  }

  # Run the Ansible playbook
  provisioner "remote-exec" {
    inline = [
      "chmod 600 /tmp/inventory /tmp/loop_playbook.yml", # Set correct permissions
      "ansible-playbook -i /tmp/inventory /tmp/loop_playbook.yml --private-key=/home/ec2-user/.ssh/ansible_key.pem" # Run the playbook
    ]
  }
}


#If I am having existing KP use this code for main.tf 

# Configure the AWS provider
# provider "aws" {
#   region = "eu-west-2" # Your region
# }

# # Use the existing key pair
# resource "aws_key_pair" "ansible_key" {
#   key_name   = "LondonKP" # Your existing key pair name
#   public_key = file("/Users/Lumla/Desktop/LondonKP.pub") # Full path to your public key on Desktop
# }

# # Create the Ansible control node
# resource "aws_instance" "ansible_control_node" {
#   ami           = "ami-0e56583ebfdfc098f" # Your AMI ID
#   instance_type = "t2.micro"
#   key_name      = aws_key_pair.ansible_key.key_name # Use the existing key pair

#   tags = {
#     Name = "Ansible-Control-Node"
#   }
# }

# # Create the target node(s)
# resource "aws_instance" "target_node" {
#   count         = 2 # Create 2 target nodes
#   ami           = "ami-0e56583ebfdfc098f" # Your AMI ID
#   instance_type = "t2.micro"
#   key_name      = aws_key_pair.ansible_key.key_name # Use the existing key pair

#   tags = {
#     Name = "Target-Node-${count.index + 1}"
#   }
# }

# # Output the public IPs of the instances
# output "ansible_control_node_public_ip" {
#   value = aws_instance.ansible_control_node.public_ip
# }

# output "target_nodes_public_ips" {
#   value = aws_instance.target_node[*].public_ip
# }

# # Generate the Ansible inventory file dynamically
# resource "local_file" "inventory" {
#   filename = "inventory"
#   content  = <<-EOT
#     [target_hosts]
#     %{ for ip in aws_instance.target_node[*].public_ip ~}
#     ${ip}
#     %{ endfor ~}
#   EOT
# }

# # Run the Ansible playbook from the control node
# resource "null_resource" "run_ansible" {
#   depends_on = [aws_instance.ansible_control_node, aws_instance.target_node, local_file.inventory]

#   provisioner "remote-exec" {
#     inline = [
#       "sudo yum install -y ansible", # Install Ansible on the control node
#       "ansible-playbook -i /tmp/inventory /tmp/loop_playbook.yml"
#     ]

#     connection {
#       type        = "ssh"
#       user        = "ec2-user" # Default user for Amazon Linux
#       private_key = file("/Users/Lumla/Desktop/LondonKP.pem") # Full path to your private key on Desktop
#       host        = aws_instance.ansible_control_node.public_ip
#     }
#   }

#   provisioner "file" {
#     source      = "inventory"
#     destination = "/tmp/inventory"
#   }

#   provisioner "file" {
#     source      = "loop_playbook.yml"
#     destination = "/tmp/loop_playbook.yml"
#   }
# }


